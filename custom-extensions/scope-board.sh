#!/bin/bash
set -e

# Scope a GitLab board to an enhancement label using the custom extensions.
# This directly inserts into the board_labels table.
#
# Usage: ./scope-board.sh <project_path> <board_name> [label_name]
#
# If label_name is omitted, defaults to "enhancement::<board_name>"
#
# Examples:
#   ./scope-board.sh administrators/pipecat multiuser
#   ./scope-board.sh administrators/pipecat initial enhancement::initial

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_PATH="${1:?Usage: $0 <project_path> <board_name> [label_name]}"
BOARD_NAME="${2:?Usage: $0 <project_path> <board_name> [label_name]}"
LABEL_NAME="${3:-enhancement::${BOARD_NAME}}"

CONTAINER="gitlab"

echo -e "${GREEN}=== Scope Board: ${BOARD_NAME} → ${LABEL_NAME} ===${NC}"

# URL-encode project path
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's|/|%2F|g')

# Find project ID
PROJECT_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT p.id FROM projects p JOIN namespaces n ON p.namespace_id = n.id WHERE n.path || '/' || p.path = '${PROJECT_PATH}';" 2>/dev/null | tr -d ' ')

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "" ]; then
    echo -e "${RED}ERROR: Project '${PROJECT_PATH}' not found${NC}"
    exit 1
fi
echo -e "  Project ID: ${PROJECT_ID}"

# Find board ID
BOARD_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM boards WHERE project_id = ${PROJECT_ID} AND name = '${BOARD_NAME}';" 2>/dev/null | tr -d ' ')

if [ -z "$BOARD_ID" ] || [ "$BOARD_ID" = "" ]; then
    echo -e "${RED}ERROR: Board '${BOARD_NAME}' not found in project${NC}"
    exit 1
fi
echo -e "  Board ID: ${BOARD_ID}"

# Find label ID
LABEL_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM labels WHERE title = '${LABEL_NAME}' AND project_id = ${PROJECT_ID};" 2>/dev/null | tr -d ' ')

if [ -z "$LABEL_ID" ] || [ "$LABEL_ID" = "" ]; then
    # Try group labels
    GROUP_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
        "SELECT namespace_id FROM projects WHERE id = ${PROJECT_ID};" 2>/dev/null | tr -d ' ')
    LABEL_ID=$(docker exec "$CONTAINER" gitlab-psql -t -c \
        "SELECT id FROM labels WHERE title = '${LABEL_NAME}' AND group_id = ${GROUP_ID};" 2>/dev/null | tr -d ' ')
fi

if [ -z "$LABEL_ID" ] || [ "$LABEL_ID" = "" ]; then
    echo -e "${RED}ERROR: Label '${LABEL_NAME}' not found${NC}"
    exit 1
fi
echo -e "  Label ID: ${LABEL_ID}"

# Check if already scoped
EXISTING=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT id FROM board_labels WHERE board_id = ${BOARD_ID} AND label_id = ${LABEL_ID};" 2>/dev/null | tr -d ' ')

if [ -n "$EXISTING" ] && [ "$EXISTING" != "" ]; then
    echo -e "${YELLOW}Board '${BOARD_NAME}' already scoped to '${LABEL_NAME}'${NC}"
    exit 0
fi

# Insert board_label
docker exec "$CONTAINER" gitlab-psql -c \
    "INSERT INTO board_labels (board_id, label_id, project_id) VALUES (${BOARD_ID}, ${LABEL_ID}, ${PROJECT_ID});" 2>/dev/null

echo -e "${GREEN}✓ Board '${BOARD_NAME}' now scoped to label '${LABEL_NAME}'${NC}"

# Verify
COUNT=$(docker exec "$CONTAINER" gitlab-psql -t -c \
    "SELECT count(*) FROM board_labels WHERE board_id = ${BOARD_ID};" 2>/dev/null | tr -d ' ')
echo -e "  Board has ${COUNT} scope label(s)"
