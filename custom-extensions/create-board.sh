#!/bin/bash
set -e

# Create a new GitLab board with standard columns and label scoping.
# Works around GitLab CE limitation (only 1 board via API) by using direct SQL.
#
# Usage: ./create-board.sh <project_path> <board_name> [label_name]
#
# If label_name is omitted, defaults to "enhancement::<board_name>"
#
# What it does:
#   1. Creates enhancement::<board_name> label (if missing)
#   2. Creates board row in database (idempotent — skips if exists)
#   3. Adds 6 standard columns (backlog, ready, in-progress, review, blocked, done)
#   4. Scopes board to label via LX extension (board_labels table)
#
# Examples:
#   ./create-board.sh administrators/pipecat multiuser
#   ./create-board.sh administrators/vikunja crossproject
#   ./create-board.sh administrators/cicd initial enhancement::initial

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_PATH="${1:?Usage: $0 <project_path> <board_name> [label_name]}"
BOARD_NAME="${2:?Usage: $0 <project_path> <board_name> [label_name]}"
LABEL_NAME="${3:-enhancement::${BOARD_NAME}}"

CONTAINER="gitlab"
GLAB="/home/administrator/projects/devscripts/glab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}=== Create Board: ${BOARD_NAME} (${PROJECT_PATH}) ===${NC}"

# Extract group from project path
GROUP=$(echo "$PROJECT_PATH" | cut -d'/' -f1)
PROJECT=$(echo "$PROJECT_PATH" | cut -d'/' -f2)

# Map group to ID
case "$GROUP" in
    administrators) GROUP_ID=10 ;;
    developers)     GROUP_ID=13 ;;
    *)
        echo -e "${RED}ERROR: Unknown group '${GROUP}'. Expected administrators or developers.${NC}"
        exit 1
        ;;
esac

# Find project ID
PROJECT_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT p.id FROM projects p JOIN namespaces n ON p.namespace_id = n.id WHERE n.path = '${GROUP}' AND p.path = '${PROJECT}';" 2>/dev/null | tr -d ' ')

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "" ]; then
    echo -e "${RED}ERROR: Project '${PROJECT_PATH}' not found${NC}"
    exit 1
fi
echo -e "  Project ID: ${PROJECT_ID}"

# Step 1: Create enhancement label if missing
echo -e "  Checking label '${LABEL_NAME}'..."
EXISTING_LABEL=$($GLAB api "projects/${GROUP}%2F${PROJECT}/labels" --per-page 100 2>/dev/null | \
    jq -r ".[] | select(.name==\"${LABEL_NAME}\") | .id" 2>/dev/null || echo "")

if [ -z "$EXISTING_LABEL" ]; then
    # Check group-level labels too
    EXISTING_LABEL=$($GLAB api "groups/${GROUP_ID}/labels?per_page=100" 2>/dev/null | \
        jq -r ".[] | select(.name==\"${LABEL_NAME}\") | .id" 2>/dev/null || echo "")
fi

if [ -z "$EXISTING_LABEL" ]; then
    echo -e "  Creating label '${LABEL_NAME}'..."
    $GLAB api -X POST "projects/${GROUP}%2F${PROJECT}/labels" \
        --raw-field "name=${LABEL_NAME}" \
        --raw-field "color=#6699cc" \
        --raw-field "description=Board scope: ${BOARD_NAME}" 2>/dev/null | jq -r '.id' > /dev/null
    echo -e "  ${GREEN}✓ Label created${NC}"
else
    echo -e "  ${YELLOW}Label already exists (ID: ${EXISTING_LABEL})${NC}"
fi

# Step 2: Create board if missing
BOARD_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM boards WHERE project_id = ${PROJECT_ID} AND name = '${BOARD_NAME}';" 2>/dev/null | tr -d ' \n')

if [ -z "$BOARD_ID" ] || [ "$BOARD_ID" = "" ]; then
    echo -e "  Creating board '${BOARD_NAME}'..."
    BOARD_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
        "INSERT INTO boards (project_id, name, created_at, updated_at) VALUES (${PROJECT_ID}, '${BOARD_NAME}', NOW(), NOW()) RETURNING id;" 2>/dev/null | tr -d ' \n')
    echo -e "  ${GREEN}✓ Board created (ID: ${BOARD_ID})${NC}"
else
    echo -e "  ${YELLOW}Board already exists (ID: ${BOARD_ID})${NC}"
fi

# Step 3: Add standard columns (skip if already has lists)
LIST_COUNT=$($GLAB api "projects/${GROUP}%2F${PROJECT}/boards/${BOARD_ID}/lists" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")

if [ "$LIST_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}Board already has ${LIST_COUNT} columns — skipping column creation${NC}"
else
    echo -e "  Adding standard columns..."
    # Get group-level label IDs for columns
    LABELS_JSON=$($GLAB api "groups/${GROUP_ID}/labels?per_page=100" 2>/dev/null)

    for COL_NAME in backlog ready in-progress review blocked done; do
        COL_LABEL_ID=$(echo "$LABELS_JSON" | jq -r ".[] | select(.name==\"${COL_NAME}\") | .id")
        if [ -n "$COL_LABEL_ID" ] && [ "$COL_LABEL_ID" != "null" ]; then
            $GLAB api -X POST "projects/${GROUP}%2F${PROJECT}/boards/${BOARD_ID}/lists" \
                -f "label_id=${COL_LABEL_ID}" 2>/dev/null > /dev/null
            echo -e "    ${GREEN}✓${NC} ${COL_NAME}"
        else
            echo -e "    ${RED}✗${NC} ${COL_NAME} — label not found"
        fi
    done
fi

# Step 4: Scope board via LX extension
echo -e "  Scoping board..."
bash "${SCRIPT_DIR}/scope-board.sh" "$PROJECT_PATH" "$BOARD_NAME" "$LABEL_NAME"

echo -e "${GREEN}=== Board '${BOARD_NAME}' ready ===${NC}"
