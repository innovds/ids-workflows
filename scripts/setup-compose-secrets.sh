#!/bin/bash
#
# Setup GitHub secrets/variables for Compose-based VM deployments (multi-registry)
#
# Usage:
#   # Nexus registry (FlowSpace, KStar)
#   ./setup-compose-secrets.sh --group flowspace --registry nexus --host 37.59.110.100 --user ubuntu --maven
#
#   # DockerHub registry
#   ./setup-compose-secrets.sh --repo innovds/config-server --registry dockerhub --host 37.59.110.100 --user ubuntu
#
#   # GHCR registry
#   ./setup-compose-secrets.sh --repo innovds/ids-backstage --registry ghcr --host 37.59.110.100 --user ubuntu
#
#   # ECR registry (AWS OIDC)
#   ./setup-compose-secrets.sh --group ellarea --registry ecr --host 10.0.1.50 --user ec2-user --maven
#
#   # Generic private registry (client)
#   ./setup-compose-secrets.sh --repo client/app --registry generic --registry-url registry.client.com --host 10.0.0.5 --user deploy
#
#   # Dry run
#   ./setup-compose-secrets.sh --group flowspace --registry nexus --host 37.59.110.100 --user ubuntu --dry-run

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
MAVEN_SETTINGS_PATH=""
DRY_RUN=false
SETUP_MAVEN=false
REGISTRY_TYPE=""
REGISTRY_URL=""

# Repo groups
declare -A GROUPS
GROUPS[flowspace]="innovds/user-ms innovds/fs-site-ms innovds/fs-reservation-ms innovds/flowspace-main-ui"
GROUPS[flowspace-ms]="innovds/user-ms innovds/fs-site-ms innovds/fs-reservation-ms"
GROUPS[ellarea]="innovds/iam-ms innovds/profile-ms innovds/ellarea-main-ui"
GROUPS[ellarea-ms]="innovds/iam-ms innovds/profile-ms"
GROUPS[kstar]="innovds/kstar-api innovds/kstar-main-ui"

# Default registry per group (used when --registry is omitted)
declare -A GROUP_REGISTRY
GROUP_REGISTRY[flowspace]="nexus"
GROUP_REGISTRY[flowspace-ms]="nexus"
GROUP_REGISTRY[ellarea]="ecr"
GROUP_REGISTRY[ellarea-ms]="ecr"
GROUP_REGISTRY[kstar]="nexus"

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Setup GitHub secrets/variables for Compose-based VM deployments."
    echo ""
    echo "Target (one required):"
    echo "  --repo OWNER/REPO       Single repository"
    echo "  --group NAME            Repo group: ${!GROUPS[*]}"
    echo ""
    echo "Required:"
    echo "  --host IP               SSH host (VM IP)"
    echo "  --user USER             SSH user (e.g., ubuntu, ec2-user)"
    echo ""
    echo "Registry (one required, or auto-detected from group):"
    echo "  --registry TYPE         Registry type: nexus, dockerhub, ghcr, ecr, generic"
    echo "  --registry-url URL      Registry URL (required for generic, optional for nexus)"
    echo ""
    echo "Options:"
    echo "  --ssh-key PATH          SSH private key (default: ~/.ssh/id_rsa)"
    echo "  --maven                 Also set MAVEN_SETTINGS_XML (for Java MS)"
    echo "  --maven-file PATH       Maven settings file (default: auto-detect)"
    echo "  --dry-run               Show what would be done without executing"
    echo "  --help                  Show this help"
    echo ""
    echo "Registry types and secrets configured:"
    echo "  nexus     : NEXUS_USERNAME, NEXUS_PASSWORD"
    echo "  dockerhub : DOCKERHUB_USERNAME, DOCKERHUB_TOKEN"
    echo "  ghcr      : GHCR_USERNAME, GHCR_TOKEN"
    echo "  ecr       : AWS_ROLE_TO_ASSUME (OIDC, no username/password)"
    echo "  generic   : REGISTRY_URL (var), REGISTRY_USERNAME, REGISTRY_PASSWORD"
    echo ""
    echo "Common secrets (always set):"
    echo "  SSH_PRIVATE_KEY (secret), SSH_HOST (var), SSH_USER (var)"
    echo "  MAVEN_SETTINGS_XML (secret, with --maven)"
    echo ""
    echo "Groups (default registry):"
    for group in "${!GROUPS[@]}"; do
        echo "  $group [${GROUP_REGISTRY[$group]:-?}]: ${GROUPS[$group]}"
    done
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[dry-run]${NC} $1"
    else
        eval "$2"
        echo -e "  ${GREEN}✓${NC} $1"
    fi
}

encode_base64() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        base64 -i "$1"
    else
        base64 -w 0 "$1"
    fi
}

prompt_secret() {
    local prompt_msg="$1"
    local var_name="$2"
    local current_val="${!var_name}"

    if [ -z "$current_val" ]; then
        read -sp "$prompt_msg: " current_val
        echo ""
        [ -z "$current_val" ] && { echo -e "${RED}Value required${NC}"; exit 1; }
        eval "$var_name='$current_val'"
    fi
}

setup_registry_secrets() {
    local repo="$1"

    case "$REGISTRY_TYPE" in
        nexus)
            prompt_secret "Nexus password for user '$REG_USER'" REG_PASS
            run_cmd "NEXUS_USERNAME=$REG_USER" "echo '$REG_USER' | gh secret set NEXUS_USERNAME -R '$repo'"
            run_cmd "NEXUS_PASSWORD" "echo '$REG_PASS' | gh secret set NEXUS_PASSWORD -R '$repo'"
            ;;
        dockerhub)
            prompt_secret "DockerHub token for user '$REG_USER'" REG_PASS
            run_cmd "DOCKERHUB_USERNAME=$REG_USER" "echo '$REG_USER' | gh secret set DOCKERHUB_USERNAME -R '$repo'"
            run_cmd "DOCKERHUB_TOKEN" "echo '$REG_PASS' | gh secret set DOCKERHUB_TOKEN -R '$repo'"
            ;;
        ghcr)
            prompt_secret "GHCR token for user '$REG_USER'" REG_PASS
            run_cmd "GHCR_USERNAME=$REG_USER" "echo '$REG_USER' | gh secret set GHCR_USERNAME -R '$repo'"
            run_cmd "GHCR_TOKEN" "echo '$REG_PASS' | gh secret set GHCR_TOKEN -R '$repo'"
            ;;
        ecr)
            [ -z "$AWS_ROLE_ARN" ] && { echo -e "${RED}--aws-role-arn required for ECR registry${NC}"; exit 1; }
            run_cmd "AWS_ROLE_TO_ASSUME" "echo '$AWS_ROLE_ARN' | gh secret set AWS_ROLE_TO_ASSUME -R '$repo'"
            ;;
        generic)
            [ -z "$REGISTRY_URL" ] && { echo -e "${RED}--registry-url required for generic registry${NC}"; exit 1; }
            prompt_secret "Registry password for user '$REG_USER' @ $REGISTRY_URL" REG_PASS
            run_cmd "REGISTRY_URL=$REGISTRY_URL" "gh variable set REGISTRY_URL -R '$repo' --body '$REGISTRY_URL'"
            run_cmd "REGISTRY_USERNAME=$REG_USER" "echo '$REG_USER' | gh secret set REGISTRY_USERNAME -R '$repo'"
            run_cmd "REGISTRY_PASSWORD" "echo '$REG_PASS' | gh secret set REGISTRY_PASSWORD -R '$repo'"
            ;;
    esac
}

main() {
    local REPOS=""
    local GROUP_NAME=""
    local SSH_HOST=""
    local SSH_USER=""
    REG_USER=""
    REG_PASS=""
    AWS_ROLE_ARN=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --repo) REPOS="$2"; shift 2 ;;
            --group)
                GROUP_NAME="$2"
                if [ -z "${GROUPS[$2]+x}" ]; then
                    echo -e "${RED}Unknown group: $2${NC}"
                    echo "Available: ${!GROUPS[*]}"
                    exit 1
                fi
                REPOS="${GROUPS[$2]}"
                shift 2
                ;;
            --registry) REGISTRY_TYPE="$2"; shift 2 ;;
            --registry-url) REGISTRY_URL="$2"; shift 2 ;;
            --registry-user) REG_USER="$2"; shift 2 ;;
            --registry-pass) REG_PASS="$2"; shift 2 ;;
            --aws-role-arn) AWS_ROLE_ARN="$2"; shift 2 ;;
            --host) SSH_HOST="$2"; shift 2 ;;
            --user) SSH_USER="$2"; shift 2 ;;
            --ssh-key) SSH_KEY_PATH="$2"; shift 2 ;;
            --maven) SETUP_MAVEN=true; shift ;;
            --maven-file) MAVEN_SETTINGS_PATH="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --help) show_help; exit 0 ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; show_help; exit 1 ;;
        esac
    done

    # Validate target
    [ -z "$REPOS" ] && { echo -e "${RED}Missing --repo or --group${NC}"; show_help; exit 1; }
    [ -z "$SSH_HOST" ] && { echo -e "${RED}Missing --host${NC}"; exit 1; }
    [ -z "$SSH_USER" ] && { echo -e "${RED}Missing --user${NC}"; exit 1; }
    [ ! -f "$SSH_KEY_PATH" ] && { echo -e "${RED}SSH key not found: $SSH_KEY_PATH${NC}"; exit 1; }

    # Auto-detect registry from group if not specified
    if [ -z "$REGISTRY_TYPE" ]; then
        if [ -n "$GROUP_NAME" ] && [ -n "${GROUP_REGISTRY[$GROUP_NAME]+x}" ]; then
            REGISTRY_TYPE="${GROUP_REGISTRY[$GROUP_NAME]}"
            echo -e "${BLUE}Auto-detected registry: $REGISTRY_TYPE (from group $GROUP_NAME)${NC}"
        else
            echo -e "${RED}Missing --registry (required for single repo, or use a group with default)${NC}"
            exit 1
        fi
    fi

    # Validate registry type
    case "$REGISTRY_TYPE" in
        nexus|dockerhub|ghcr|ecr|generic) ;;
        *) echo -e "${RED}Unknown registry type: $REGISTRY_TYPE${NC}"; echo "Valid: nexus, dockerhub, ghcr, ecr, generic"; exit 1 ;;
    esac

    # Default registry users
    if [ -z "$REG_USER" ]; then
        case "$REGISTRY_TYPE" in
            nexus) REG_USER="github" ;;
            dockerhub) REG_USER="innovds" ;;
            ghcr) REG_USER="innovds" ;;
            generic) REG_USER="deploy" ;;
        esac
    fi

    # Default Nexus URL
    if [ "$REGISTRY_TYPE" = "nexus" ] && [ -z "$REGISTRY_URL" ]; then
        REGISTRY_URL="docker.innov-ds.com"
    fi

    # Auto-detect Maven settings
    if [ "$SETUP_MAVEN" = true ] && [ -z "$MAVEN_SETTINGS_PATH" ]; then
        for path in "$HOME/.m2/settings-github.xml" "$HOME/.m2/settings.xml"; do
            [ -f "$path" ] && { MAVEN_SETTINGS_PATH="$path"; break; }
        done
        [ -z "$MAVEN_SETTINGS_PATH" ] && { echo -e "${RED}Maven settings not found (~/.m2/settings-github.xml or ~/.m2/settings.xml)${NC}"; exit 1; }
    fi

    # Summary
    echo ""
    echo "Configuration:"
    echo "  Repos:      $REPOS"
    echo "  Registry:   $REGISTRY_TYPE"
    [ -n "$REGISTRY_URL" ] && echo "  Registry URL: $REGISTRY_URL"
    [ "$REGISTRY_TYPE" != "ecr" ] && echo "  Reg user:   $REG_USER"
    [ "$REGISTRY_TYPE" = "ecr" ] && echo "  AWS Role:   $AWS_ROLE_ARN"
    echo "  SSH:        $SSH_USER@$SSH_HOST"
    echo "  SSH key:    $SSH_KEY_PATH"
    [ "$SETUP_MAVEN" = true ] && echo "  Maven:      $MAVEN_SETTINGS_PATH"
    [ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}DRY RUN${NC}"
    echo ""

    # Pre-encode Maven settings
    local MAVEN_B64=""
    if [ "$SETUP_MAVEN" = true ]; then
        MAVEN_B64=$(encode_base64 "$MAVEN_SETTINGS_PATH")
    fi

    for repo in $REPOS; do
        echo "=== $repo ==="

        # Common: SSH variables + secret
        run_cmd "SSH_HOST=$SSH_HOST" "gh variable set SSH_HOST -R '$repo' --body '$SSH_HOST'"
        run_cmd "SSH_USER=$SSH_USER" "gh variable set SSH_USER -R '$repo' --body '$SSH_USER'"
        run_cmd "SSH_PRIVATE_KEY" "gh secret set SSH_PRIVATE_KEY -R '$repo' < '$SSH_KEY_PATH'"

        # Registry-specific secrets
        setup_registry_secrets "$repo"

        # Maven (optional)
        if [ "$SETUP_MAVEN" = true ]; then
            run_cmd "MAVEN_SETTINGS_XML" "echo '$MAVEN_B64' | gh secret set MAVEN_SETTINGS_XML -R '$repo'"
        fi

        echo ""
    done

    echo -e "${GREEN}Done!${NC}"
}

main "$@"
