#!/bin/bash
#
# Initialize a microservice with IDS CI/CD workflows
#
# Usage: ./init-repo.sh /path/to/repo [service-name]
#

set -e

GREEN='\033[0;32m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $0 <repo-path> [service-name]"
    echo "Example: $0 /path/to/billing-ms"
    exit 1
fi

REPO_PATH="$1"
SERVICE_NAME="${2:-$(basename "$REPO_PATH")}"

[ ! -d "$REPO_PATH" ] && echo "Error: $REPO_PATH not found" && exit 1

echo -e "${GREEN}Initializing $SERVICE_NAME...${NC}"

mkdir -p "$REPO_PATH/.github/workflows"

# CI
cat > "$REPO_PATH/.github/workflows/ci.yml" << 'EOF'
name: CI
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: innovds/ids-workflows/.github/workflows/ci.yml@main
    with:
      run-tests: true
      build-validation: false
    secrets:
      MAVEN_SETTINGS_XML: ${{ secrets.MAVEN_SETTINGS_XML }}
EOF

# Build & Deploy (manual)
cat > "$REPO_PATH/.github/workflows/build-deploy.yml" << 'EOF'
name: Build & Deploy (Manual)
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        type: choice
        options:
          - int
          - stg
          - prod
        default: int
      run-tests:
        description: 'Run tests before build'
        required: false
        type: boolean
        default: false
      build-image:
        description: 'Build new image (uncheck to deploy existing)'
        required: false
        type: boolean
        default: true

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    uses: innovds/ids-workflows/.github/workflows/pipeline.yml@main
    with:
      run-tests: ${{ inputs.run-tests }}
      build-push: ${{ inputs.build-image }}
      deploy-env: ${{ inputs.environment }}
    secrets:
      AWS_ROLE_TO_ASSUME: ${{ secrets.AWS_ROLE_TO_ASSUME }}
      MAVEN_SETTINGS_XML: ${{ secrets.MAVEN_SETTINGS_XML }}
EOF

# Release (tag-triggered)
cat > "$REPO_PATH/.github/workflows/release.yml" << 'EOF'
name: Release
on:
  push:
    tags:
      - 'releases/v*'

permissions:
  id-token: write
  contents: read

jobs:
  release:
    uses: innovds/ids-workflows/.github/workflows/pipeline.yml@main
    with:
      run-tests: true
      build-push: true
      deploy-env: int
    secrets:
      AWS_ROLE_TO_ASSUME: ${{ secrets.AWS_ROLE_TO_ASSUME }}
      MAVEN_SETTINGS_XML: ${{ secrets.MAVEN_SETTINGS_XML }}
EOF

# SonarQube (on push to main + manual)
cat > "$REPO_PATH/.github/workflows/sonar.yml" << 'EOF'
name: SonarQube
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  sonar:
    uses: innovds/ids-workflows/.github/workflows/sonar.yml@main
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      MAVEN_SETTINGS_XML: ${{ secrets.MAVEN_SETTINGS_XML }}
EOF

echo -e "${GREEN}Done!${NC}"
echo "Created:"
echo "  - ci.yml"
echo "  - build-deploy.yml"
echo "  - release.yml"
echo "  - sonar.yml"
echo ""
echo "Next: ./setup-secrets.sh --repo innovds/${SERVICE_NAME}"
