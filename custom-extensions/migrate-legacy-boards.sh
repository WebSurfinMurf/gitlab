#!/bin/bash
set -e

# Migrate legacy boards to the enhancement::initial convention.
# Finds boards named "cicd" (or any legacy name), renames to "initial",
# adds enhancement::initial label to all unlabeled issues, and scopes the board.
#
# Usage: ./migrate-legacy-boards.sh <project_path> [old_board_name]
#
# If old_board_name is omitted, defaults to "cicd"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_PATH="${1:?Usage: $0 <project_path> [old_board_name]}"
OLD_NAME="${2:-cicd}"
NEW_NAME="initial"
LABEL_NAME="enhancement::initial"

GLAB="$HOME/projects/devscripts/glab"
CONTAINER="gitlab"

echo -e "${GREEN}=== Migrate Board: ${OLD_NAME} → ${NEW_NAME} ===${NC}"
echo -e "  Project: ${PROJECT_PATH}"

# URL-encode project path
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's|/|%2F|g')

# Find project ID
PROJECT_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM projects WHERE path_with_namespace = '${PROJECT_PATH}';" 2>/dev/null | tr -d ' ')

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}ERROR: Project '${PROJECT_PATH}' not found${NC}"
    exit 1
fi

# Check if old board exists
OLD_BOARD_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM boards WHERE project_id = ${PROJECT_ID} AND name = '${OLD_NAME}';" 2>/dev/null | tr -d ' ')

if [ -z "$OLD_BOARD_ID" ] || [ "$OLD_BOARD_ID" = "" ]; then
    echo -e "${YELLOW}No board named '${OLD_NAME}' found. Nothing to migrate.${NC}"
    exit 0
fi
echo -e "  Old board ID: ${OLD_BOARD_ID}"

# Check if new board already exists
NEW_BOARD_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM boards WHERE project_id = ${PROJECT_ID} AND name = '${NEW_NAME}';" 2>/dev/null | tr -d ' ')

if [ -n "$NEW_BOARD_ID" ] && [ "$NEW_BOARD_ID" != "" ]; then
    echo -e "${RED}ERROR: Board '${NEW_NAME}' already exists (ID: ${NEW_BOARD_ID}).${NC}"
    echo -e "${YELLOW}Delete one of the boards first, or scope them manually.${NC}"
    exit 1
fi

# Create enhancement::initial label if it doesn't exist
LABEL_EXISTS=$($GLAB api "projects/${ENCODED_PATH}/labels" 2>/dev/null | \
    jq -r ".[] | select(.name==\"${LABEL_NAME}\") | .name")

if [ -z "$LABEL_EXISTS" ]; then
    echo -e "${YELLOW}Creating label '${LABEL_NAME}'...${NC}"
    $GLAB api -X POST "projects/${ENCODED_PATH}/labels" \
        --raw-field "name=${LABEL_NAME}" \
        --raw-field "color=#428BCA" 2>/dev/null | jq -r '.name'
else
    echo -e "  Label '${LABEL_NAME}': ${GREEN}exists${NC}"
fi

# Find issues WITHOUT any enhancement:: label (these are the legacy ones)
echo -e "${YELLOW}Finding issues without enhancement:: labels...${NC}"
ISSUE_IIDS=$(docker exec "$CONTAINER" gitlab-psql -t -c "
    SELECT i.iid FROM issues i
    WHERE i.project_id = ${PROJECT_ID}
    AND NOT EXISTS (
        SELECT 1 FROM label_links ll
        JOIN labels l ON l.id = ll.label_id
        WHERE ll.target_id = i.id
        AND ll.target_type = 'Issue'
        AND l.title LIKE 'enhancement::%'
    )
    ORDER BY i.iid;" 2>/dev/null | tr -d ' ' | grep -v '^$')

ISSUE_COUNT=$(echo "$ISSUE_IIDS" | grep -c . 2>/dev/null || echo "0")
echo -e "  Found ${ISSUE_COUNT} issues to label"

# Add enhancement::initial label to each issue
if [ "$ISSUE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Adding '${LABEL_NAME}' to issues...${NC}"
    for IID in $ISSUE_IIDS; do
        CURRENT=$($GLAB api "projects/${ENCODED_PATH}/issues/${IID}" 2>/dev/null | jq -r '[.labels[]] | join(",")')
        NEW_LABELS="${CURRENT},${LABEL_NAME}"
        $GLAB api -X PUT "projects/${ENCODED_PATH}/issues/${IID}" \
            --raw-field "labels=${NEW_LABELS}" 2>/dev/null | jq -r '"\(.iid): OK"'
    done
fi

# Rename the board
echo -e "${YELLOW}Renaming board '${OLD_NAME}' → '${NEW_NAME}'...${NC}"
docker exec "$CONTAINER" gitlab-psql -c \
    "UPDATE boards SET name = '${NEW_NAME}' WHERE id = ${OLD_BOARD_ID};" 2>/dev/null
echo -e "  ${GREEN}Renamed${NC}"

# Scope the board using scope-board.sh
echo -e "${YELLOW}Scoping board...${NC}"
"${SCRIPT_DIR:-$(dirname "$0")}/scope-board.sh" "$PROJECT_PATH" "$NEW_NAME" "$LABEL_NAME"

echo ""
echo -e "${GREEN}=== Migration Complete ===${NC}"
echo -e "  Board: ${OLD_NAME} → ${NEW_NAME}"
echo -e "  Label: ${LABEL_NAME}"
echo -e "  Issues labeled: ${ISSUE_COUNT}"
