#!/bin/bash
#
# Render templates with config values
#
# Usage:
#   ./scripts/render.sh                    # Uses config.local.sh or config.example.sh
#   ./scripts/render.sh config.client.sh   # Uses specific config file
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load config
CONFIG_FILE="${1:-}"
if [ -z "$CONFIG_FILE" ]; then
    if [ -f "$ROOT_DIR/config.local.sh" ]; then
        CONFIG_FILE="$ROOT_DIR/config.local.sh"
    else
        CONFIG_FILE="$ROOT_DIR/config.example.sh"
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    echo "Create config.local.sh from config.example.sh"
    exit 1
fi

echo -e "${GREEN}Loading config: $CONFIG_FILE${NC}"
source "$CONFIG_FILE"

# Derive ECR_REGISTRY if not set
ECR_REGISTRY="${ECR_REGISTRY:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com}"

echo "  ORG_NAME=$ORG_NAME"
echo "  AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "  AWS_REGION=$AWS_REGION"
echo "  ECR_REGISTRY=$ECR_REGISTRY"
echo ""

# Render function
render_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    sed -e "s|{{ORG_NAME}}|$ORG_NAME|g" \
        -e "s|{{AWS_ACCOUNT_ID}}|$AWS_ACCOUNT_ID|g" \
        -e "s|{{AWS_REGION}}|$AWS_REGION|g" \
        -e "s|{{ECR_REGISTRY}}|$ECR_REGISTRY|g" \
        "$src" > "$dst"

    # Preserve executable permission
    if [ -x "$src" ]; then
        chmod +x "$dst"
    fi

    echo "  ✓ $(basename "$dst")"
}

# Render workflows
echo -e "${GREEN}Rendering workflows...${NC}"
for src in "$ROOT_DIR/templates/.github/workflows/"*.yml; do
    [ -f "$src" ] || continue
    dst="$ROOT_DIR/.github/workflows/$(basename "$src")"
    render_file "$src" "$dst"
done

# Render actions
echo -e "${GREEN}Rendering actions...${NC}"
for action_dir in "$ROOT_DIR/templates/actions/"*/; do
    [ -d "$action_dir" ] || continue
    action_name="$(basename "$action_dir")"
    src="$action_dir/action.yml"
    dst="$ROOT_DIR/actions/$action_name/action.yml"
    if [ -f "$src" ]; then
        render_file "$src" "$dst"
    fi
done

# Render scripts
echo -e "${GREEN}Rendering scripts...${NC}"
for src in "$ROOT_DIR/templates/scripts/"*.sh; do
    [ -f "$src" ] || continue
    dst="$ROOT_DIR/scripts/$(basename "$src")"
    render_file "$src" "$dst"
done

echo ""
echo -e "${GREEN}Done!${NC} Files rendered for org: $ORG_NAME"
echo ""
echo -e "${YELLOW}Next: Review changes and commit${NC}"
