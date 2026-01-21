#!/bin/bash
#
# Initialize a microservice with IDS CI/CD workflows
#
# Usage: ./init-repo.sh /path/to/repo service-name
#

set -e

GREEN='\033[0;32m'
NC='\033[0m'

if [ $# -lt 2 ]; then
    echo "Usage: $0 <repo-path> <service-name>"
    echo "Example: $0 /path/to/billing-ms billing-ms"
    exit 1
fi

REPO_PATH="$1"
SERVICE_NAME="$2"

[ ! -d "$REPO_PATH" ] && echo "Error: $REPO_PATH not found" && exit 1

echo -e "${GREEN}Initializing $SERVICE_NAME...${NC}"

mkdir -p "$REPO_PATH/.github/workflows"

# CI
cat > "$REPO_PATH/.github/workflows/ci.yml" << EOF
name: CI
on:
  pull_request:
    branches: [main]

jobs:
  test:
    uses: {{ORG_NAME}}/ids-workflows/.github/workflows/ms-pipeline.yml@main
    with:
      service-name: ${SERVICE_NAME}
      run-tests: true
    secrets:
      MAVEN_SETTINGS_XML: \${{ secrets.MAVEN_SETTINGS_XML }}
EOF

# Build & Deploy INT
cat > "$REPO_PATH/.github/workflows/build-deploy.yml" << EOF
name: Build & Deploy INT
on:
  push:
    branches: [main]

jobs:
  pipeline:
    uses: {{ORG_NAME}}/ids-workflows/.github/workflows/ms-pipeline.yml@main
    with:
      service-name: ${SERVICE_NAME}
      run-tests: true
      build-push: true
      deploy-env: int
    secrets:
      AWS_ROLE_TO_ASSUME: \${{ secrets.AWS_ROLE_TO_ASSUME }}
      MAVEN_SETTINGS_XML: \${{ secrets.MAVEN_SETTINGS_XML }}
EOF

# Deploy STG
cat > "$REPO_PATH/.github/workflows/deploy-stg.yml" << EOF
name: Deploy STG
on:
  workflow_dispatch:
    inputs:
      image-tag:
        description: 'Image tag (e.g., sha-abc1234)'
        required: true

jobs:
  deploy:
    uses: {{ORG_NAME}}/ids-workflows/.github/workflows/ms-pipeline.yml@main
    with:
      service-name: ${SERVICE_NAME}
      run-tests: false
      build-push: false
      deploy-env: stg
      image-tag: \${{ inputs.image-tag }}
    secrets:
      AWS_ROLE_TO_ASSUME: \${{ secrets.AWS_ROLE_TO_ASSUME }}
EOF

# Deploy PROD
cat > "$REPO_PATH/.github/workflows/deploy-prod.yml" << EOF
name: Deploy PROD
on:
  workflow_dispatch:
    inputs:
      image-tag:
        description: 'Image tag (e.g., sha-abc1234)'
        required: true

jobs:
  deploy:
    uses: {{ORG_NAME}}/ids-workflows/.github/workflows/ms-pipeline.yml@main
    with:
      service-name: ${SERVICE_NAME}
      run-tests: false
      build-push: false
      deploy-env: prod
      image-tag: \${{ inputs.image-tag }}
    secrets:
      AWS_ROLE_TO_ASSUME: \${{ secrets.AWS_ROLE_TO_ASSUME }}
EOF

echo -e "${GREEN}Done!${NC}"
echo "Created:"
echo "  - ci.yml (13 lines)"
echo "  - build-deploy.yml (17 lines)"
echo "  - deploy-stg.yml (19 lines)"
echo "  - deploy-prod.yml (19 lines)"
echo ""
echo "Next: ./setup-secrets.sh --repo {{ORG_NAME}}/${SERVICE_NAME}"
