#!/bin/bash
#
# Setup GitHub secrets for IDS microservices CI/CD
# For GitHub Organization FREE (no shared org secrets)
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - AWS CLI configured (optional, for OIDC setup)
#
# Usage:
#   ./setup-secrets.sh --repo innovds/iam-ms
#   ./setup-secrets.sh --repo innovds/iam-ms --skip-aws
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
AWS_REGION="eu-west-1"
AWS_ACCOUNT_ID="857736876208"
SKIP_AWS=false

print_header() { echo -e "\n${GREEN}=== $1 ===${NC}\n"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

show_help() {
    echo "Usage: $0 --repo OWNER/REPO [OPTIONS]"
    echo ""
    echo "Setup GitHub secrets for a microservice repository."
    echo "For GitHub Organization FREE (secrets must be set per repository)."
    echo ""
    echo "Required:"
    echo "  --repo OWNER/REPO    Repository (e.g., innovds/iam-ms)"
    echo ""
    echo "Options:"
    echo "  --skip-aws           Skip AWS OIDC setup"
    echo "  --help               Show this help"
    echo ""
    echo "Secrets configured:"
    echo "  - MAVEN_SETTINGS_XML : Base64 encoded ~/.m2/settings.xml"
    echo "  - AWS_ROLE_TO_ASSUME : AWS IAM Role ARN for OIDC"
    echo ""
    echo "Example:"
    echo "  $0 --repo innovds/iam-ms"
    echo "  $0 --repo innovds/billing-ms --skip-aws"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites"

    if ! command -v gh &> /dev/null; then
        print_error "gh CLI not found. Install: https://cli.github.com/"
        exit 1
    fi
    print_success "gh CLI found"

    if ! gh auth status &> /dev/null; then
        print_error "gh CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    print_success "gh CLI authenticated"

    if [ "$SKIP_AWS" = false ]; then
        if ! command -v aws &> /dev/null; then
            print_warning "AWS CLI not found. Use --skip-aws to skip AWS setup."
            SKIP_AWS=true
        else
            print_success "AWS CLI found"
        fi
    fi
}

# Encode file to base64
encode_base64() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        base64 -i "$1"
    else
        base64 -w 0 "$1"
    fi
}

# Setup Maven settings secret
setup_maven_settings() {
    print_header "Setting up Maven settings"

    MAVEN_SETTINGS_PATH="$HOME/.m2/settings.xml"

    if [ ! -f "$MAVEN_SETTINGS_PATH" ]; then
        print_warning "Maven settings.xml not found at $MAVEN_SETTINGS_PATH"
        echo ""
        echo "Create a settings.xml with your repository credentials:"
        echo ""
        cat << 'EOF'
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>YOUR_GITHUB_USERNAME</username>
      <password>YOUR_GITHUB_TOKEN</password>
    </server>
  </servers>
</settings>
EOF
        echo ""
        read -p "Press Enter after creating settings.xml, or Ctrl+C to abort..."

        if [ ! -f "$MAVEN_SETTINGS_PATH" ]; then
            print_error "settings.xml still not found. Aborting."
            exit 1
        fi
    fi

    print_success "Found settings.xml at $MAVEN_SETTINGS_PATH"

    # Encode to base64
    MAVEN_SETTINGS_B64=$(encode_base64 "$MAVEN_SETTINGS_PATH")

    echo "Setting MAVEN_SETTINGS_XML for repo: $REPO"
    echo "$MAVEN_SETTINGS_B64" | gh secret set MAVEN_SETTINGS_XML --repo "$REPO"

    print_success "MAVEN_SETTINGS_XML secret configured"
}

# Setup AWS OIDC Role
setup_aws_oidc() {
    print_header "Setting up AWS OIDC"

    if [ "$SKIP_AWS" = true ]; then
        print_warning "Skipping AWS OIDC setup"
        return 0
    fi

    ROLE_NAME="github-actions-role"
    OIDC_PROVIDER="token.actions.githubusercontent.com"
    ORG=$(echo "$REPO" | cut -d'/' -f1)

    # Check if OIDC provider exists
    print_info "Checking OIDC provider..."
    if ! aws iam get-open-id-connect-provider \
        --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}" \
        &> /dev/null; then

        echo "Creating OIDC provider for GitHub Actions..."

        THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

        aws iam create-open-id-connect-provider \
            --url "https://${OIDC_PROVIDER}" \
            --client-id-list "sts.amazonaws.com" \
            --thumbprint-list "$THUMBPRINT" \
            > /dev/null

        print_success "OIDC provider created"
    else
        print_success "OIDC provider already exists"
    fi

    # Check if role exists
    print_info "Checking IAM role..."
    if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        echo "Creating IAM role: $ROLE_NAME"

        # Create trust policy
        TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_PROVIDER}:sub": "repo:${ORG}/*:*"
        }
      }
    }
  ]
}
EOF
)

        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            > /dev/null

        print_success "IAM role created"

        # Attach ECR policy
        echo "Attaching ECR policy..."
        ECR_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/app/*"
    }
  ]
}
EOF
)

        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name "ecr-access" \
            --policy-document "$ECR_POLICY"

        # Attach ECS policy
        echo "Attaching ECS policy..."
        ECS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole"
    }
  ]
}
EOF
)

        aws iam put-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name "ecs-deploy" \
            --policy-document "$ECS_POLICY"

        print_success "Policies attached"
    else
        print_success "IAM role already exists"
    fi

    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

    echo "Setting AWS_ROLE_TO_ASSUME for repo: $REPO"
    echo "$ROLE_ARN" | gh secret set AWS_ROLE_TO_ASSUME --repo "$REPO"

    print_success "AWS_ROLE_TO_ASSUME secret configured: $ROLE_ARN"
}

# Setup GitHub environments
setup_environments() {
    print_header "Setting up GitHub Environments"

    for env in int stg prod; do
        echo "Creating environment: $env"

        gh api --method PUT "repos/${REPO}/environments/${env}" \
            2>/dev/null || print_warning "Could not create environment '$env'"
    done

    print_success "Environments created (int, stg, prod)"
    print_warning "Add required reviewers for 'prod' manually: https://github.com/${REPO}/settings/environments"
}

# Setup branch protection
setup_branch_protection() {
    print_header "Setting up Branch Protection"

    echo "Configuring branch protection for 'main'..."

    gh api --method PUT "repos/${REPO}/branches/main/protection" \
        --input - << 'EOF' 2>/dev/null || print_warning "Could not set branch protection (may need admin access)"
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["test"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF

    print_success "Branch protection configured"
}

# Main
main() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════╗"
    echo "║  IDS CI/CD Secrets Setup (GitHub Free)        ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --repo)
                REPO="$2"
                shift 2
                ;;
            --skip-aws)
                SKIP_AWS=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [ -z "$REPO" ]; then
        print_error "Missing required --repo argument"
        show_help
        exit 1
    fi

    echo "Repository: $REPO"
    echo ""

    check_prerequisites
    setup_maven_settings
    setup_aws_oidc
    setup_environments
    setup_branch_protection

    print_header "Setup Complete!"

    echo "Secrets configured for $REPO:"
    echo "  ✓ MAVEN_SETTINGS_XML"
    if [ "$SKIP_AWS" = false ]; then
        echo "  ✓ AWS_ROLE_TO_ASSUME"
    fi
    echo ""
    echo "Environments created:"
    echo "  ✓ int (auto-deploy)"
    echo "  ✓ stg (manual)"
    echo "  ✓ prod (manual + approval needed)"
    echo ""
    echo "Next steps:"
    echo "  1. Add required reviewers for 'prod': https://github.com/${REPO}/settings/environments"
    echo "  2. Verify secrets: https://github.com/${REPO}/settings/secrets/actions"
    echo "  3. Create a PR to test CI workflow"
}

main "$@"
