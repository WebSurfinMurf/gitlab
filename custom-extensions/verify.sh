#!/bin/bash
set -e

# Verify custom extensions are working correctly.
# Run after apply.sh to confirm everything loaded.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTAINER="gitlab"
RAILS_ROOT="/opt/gitlab/embedded/service/gitlab-rails"
ERRORS=0

echo -e "${GREEN}=== Verify Custom Extensions ===${NC}"

# Check 1: GitlabEdition.extensions includes 'lx'
echo -n "  GitlabEdition.extensions: "
RESULT=$(docker exec "$CONTAINER" gitlab-rails runner 'puts GitlabEdition.extensions.inspect' 2>/dev/null)
if echo "$RESULT" | grep -q "lx"; then
    echo -e "${GREEN}OK${NC} (${RESULT})"
else
    echo -e "${RED}FAILED${NC} (${RESULT})"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Board model has board_labels association
echo -n "  Board#board_labels: "
RESULT=$(docker exec "$CONTAINER" gitlab-rails runner 'puts Board.new.respond_to?(:board_labels)' 2>/dev/null)
if [ "$RESULT" = "true" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC} (respond_to? = ${RESULT})"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: Board#scoped? works (should be false for unscoped boards)
echo -n "  Board#scoped? (unscoped): "
RESULT=$(docker exec "$CONTAINER" gitlab-rails runner '
  b = Board.first
  if b
    puts b.scoped?
  else
    puts "no_boards"
  end
' 2>/dev/null)
if [ "$RESULT" = "false" ] || [ "$RESULT" = "no_boards" ]; then
    echo -e "${GREEN}OK${NC} (${RESULT})"
else
    echo -e "${RED}FAILED${NC} (${RESULT})"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: LX::BoardLabel model works
echo -n "  LX::BoardLabel: "
RESULT=$(docker exec "$CONTAINER" gitlab-rails runner 'puts LX::BoardLabel.count' 2>/dev/null)
if echo "$RESULT" | grep -qE '^[0-9]+$'; then
    echo -e "${GREEN}OK${NC} (${RESULT} rows)"
else
    echo -e "${RED}FAILED${NC} (${RESULT})"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Extension files present
echo -n "  Extension files: "
FILE_COUNT=$(docker exec "$CONTAINER" find "${RAILS_ROOT}/lx" -name "*.rb" 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -ge 5 ]; then
    echo -e "${GREEN}OK${NC} (${FILE_COUNT} files)"
else
    echo -e "${RED}FAILED${NC} (only ${FILE_COUNT} files)"
    ERRORS=$((ERRORS + 1))
fi

# Check 6: board_labels table accessible
echo -n "  board_labels table: "
RESULT=$(docker exec "$CONTAINER" gitlab-psql -t -c "SELECT count(*) FROM board_labels;" 2>/dev/null | tr -d ' ')
if echo "$RESULT" | grep -qE '^[0-9]+$'; then
    echo -e "${GREEN}OK${NC} (${RESULT} rows)"
else
    echo -e "${RED}FAILED${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}=== All checks passed ===${NC}"
else
    echo -e "${RED}=== ${ERRORS} check(s) failed ===${NC}"
    exit 1
fi
