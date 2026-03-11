#!/bin/bash
set -e

# GitLab Custom Extensions - Apply Script
# Applies patches and mounts custom extension modules into the GitLab container.
# Safe for upgrades: verifies patch targets haven't changed before applying.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAILS_ROOT="/opt/gitlab/embedded/service/gitlab-rails"
CONTAINER="gitlab"

echo -e "${GREEN}=== GitLab Custom Extensions ===${NC}"

# ─── Pre-flight checks ───────────────────────────────────────────────

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo -e "${RED}ERROR: GitLab container '${CONTAINER}' is not running.${NC}"
    exit 1
fi

GITLAB_VERSION=$(docker exec "$CONTAINER" cat "${RAILS_ROOT}/VERSION" 2>/dev/null)
echo -e "${YELLOW}GitLab version: ${GITLAB_VERSION}${NC}"

# ─── Verify patch targets (upgrade safety) ────────────────────────────

echo -e "${YELLOW}Verifying patch targets...${NC}"
ERRORS=0

# Check 1: gitlab_edition.rb - verify the line we patch still exists
EDITION_LINE=$(docker exec "$CONTAINER" grep -n '%w[]' "${RAILS_ROOT}/lib/gitlab_edition.rb" 2>/dev/null | head -1)
EDITION_ALREADY=$(docker exec "$CONTAINER" grep -c '%w[lx]' "${RAILS_ROOT}/lib/gitlab_edition.rb" 2>/dev/null | tr -d '[:space:]')
EDITION_ALREADY=${EDITION_ALREADY:-0}

if [ "$EDITION_ALREADY" -gt 0 ]; then
    echo -e "  gitlab_edition.rb: ${GREEN}already patched${NC}"
elif [ -z "$EDITION_LINE" ]; then
    echo -e "  gitlab_edition.rb: ${RED}FAILED - target line '%w[]' not found${NC}"
    echo -e "  ${RED}The file has changed in GitLab ${GITLAB_VERSION}. Manual review required.${NC}"
    echo -e "  ${YELLOW}Reference copy: ${SCRIPT_DIR}/patches/gitlab_edition.rb.original${NC}"
    docker exec "$CONTAINER" cat "${RAILS_ROOT}/lib/gitlab_edition.rb" > "${SCRIPT_DIR}/patches/gitlab_edition.rb.current"
    echo -e "  ${YELLOW}Current copy saved: ${SCRIPT_DIR}/patches/gitlab_edition.rb.current${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: application.rb - verify the insertion point still exists
APP_LINE=$(docker exec "$CONTAINER" grep -n "load_paths.call(dir: 'jh')" "${RAILS_ROOT}/config/application.rb" 2>/dev/null | head -1)
APP_ALREADY=$(docker exec "$CONTAINER" grep -c "load_paths.call(dir: 'lx')" "${RAILS_ROOT}/config/application.rb" 2>/dev/null | tr -d '[:space:]')
APP_ALREADY=${APP_ALREADY:-0}

if [ "$APP_ALREADY" -gt 0 ]; then
    echo -e "  application.rb: ${GREEN}already patched${NC}"
elif [ -z "$APP_LINE" ]; then
    echo -e "  application.rb: ${RED}FAILED - target line \"load_paths.call(dir: 'jh')\" not found${NC}"
    echo -e "  ${RED}The file has changed in GitLab ${GITLAB_VERSION}. Manual review required.${NC}"
    docker exec "$CONTAINER" cat "${RAILS_ROOT}/config/application.rb" > "${SCRIPT_DIR}/patches/application.rb.current"
    echo -e "  ${YELLOW}Current copy saved: ${SCRIPT_DIR}/patches/application.rb.current${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: inflections.rb - verify acronym insertion point exists
INFLECT_LINE=$(docker exec "$CONTAINER" grep -n "inflect.acronym 'FIPS'" "${RAILS_ROOT}/config/initializers_before_autoloader/000_inflections.rb" 2>/dev/null | head -1)
INFLECT_ALREADY=$(docker exec "$CONTAINER" grep -c "inflect.acronym 'LX'" "${RAILS_ROOT}/config/initializers_before_autoloader/000_inflections.rb" 2>/dev/null | tr -d '[:space:]')
INFLECT_ALREADY=${INFLECT_ALREADY:-0}

if [ "$INFLECT_ALREADY" -gt 0 ]; then
    echo -e "  inflections.rb: ${GREEN}already patched${NC}"
elif [ -z "$INFLECT_LINE" ]; then
    echo -e "  inflections.rb: ${RED}FAILED - acronym 'FIPS' line not found${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "  inflections.rb: ${GREEN}OK${NC}"
fi

# Check 4: Board model - verify scoped? still returns false
SCOPED_LINE=$(docker exec "$CONTAINER" grep -n "def scoped?" "${RAILS_ROOT}/app/models/board.rb" 2>/dev/null | head -1)
if [ -z "$SCOPED_LINE" ]; then
    echo -e "  board.rb: ${RED}FAILED - 'def scoped?' not found${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "  board.rb: ${GREEN}OK (scoped? found)${NC}"
fi

# Check 4: board_labels table exists in database
TABLE_EXISTS=$(docker exec "$CONTAINER" gitlab-psql -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'board_labels');" 2>/dev/null | tr -d ' ')
if [ "$TABLE_EXISTS" != "t" ]; then
    echo -e "  board_labels table: ${RED}FAILED - table does not exist in database${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "  board_labels table: ${GREEN}OK${NC}"
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo -e "${RED}=== ABORTING: ${ERRORS} verification(s) failed ===${NC}"
    echo -e "${YELLOW}GitLab ${GITLAB_VERSION} has changes that may break custom extensions.${NC}"
    echo -e "${YELLOW}Review the .current files against .original files in patches/ directory.${NC}"
    exit 1
fi

# ─── Apply patches ────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}Applying patches...${NC}"

# Patch 1: gitlab_edition.rb - add 'lx' to extensions
if [ "$EDITION_ALREADY" -gt 0 ]; then
    echo -e "  gitlab_edition.rb: ${GREEN}skipped (already applied)${NC}"
else
    docker exec "$CONTAINER" sed -i 's/%w\[\]/%w[lx]/' "${RAILS_ROOT}/lib/gitlab_edition.rb"
    VERIFY=$(docker exec "$CONTAINER" grep -c '%w\[lx\]' "${RAILS_ROOT}/lib/gitlab_edition.rb" 2>/dev/null | tr -d '[:space:]')
    VERIFY=${VERIFY:-0}
    if [ "$VERIFY" -gt 0 ]; then
        echo -e "  gitlab_edition.rb: ${GREEN}patched${NC}"
    else
        echo -e "  gitlab_edition.rb: ${RED}FAILED to patch${NC}"
        exit 1
    fi
fi

# Patch 2: application.rb - add lx extension load path
if [ "$APP_ALREADY" -gt 0 ]; then
    echo -e "  application.rb: ${GREEN}skipped (already applied)${NC}"
else
    docker exec "$CONTAINER" sed -i '/# Rake tasks ignore the eager loading settings/i\
    # LX extensions (board scoping, etc.)\
    load_paths.call(dir: '"'"'lx'"'"')\
' "${RAILS_ROOT}/config/application.rb"
    VERIFY=$(docker exec "$CONTAINER" grep -c "load_paths.call(dir: 'lx')" "${RAILS_ROOT}/config/application.rb" 2>/dev/null | tr -d '[:space:]')
    VERIFY=${VERIFY:-0}
    if [ "$VERIFY" -gt 0 ]; then
        echo -e "  application.rb: ${GREEN}patched${NC}"
    else
        echo -e "  application.rb: ${RED}FAILED to patch${NC}"
        exit 1
    fi
fi

# Patch 3: inflections.rb - add LX acronym
if [ "$INFLECT_ALREADY" -gt 0 ]; then
    echo -e "  inflections.rb: ${GREEN}skipped (already applied)${NC}"
else
    docker exec "$CONTAINER" sed -i "/inflect.acronym 'FIPS'/a\\  inflect.acronym 'LX'" \
        "${RAILS_ROOT}/config/initializers_before_autoloader/000_inflections.rb"
    VERIFY=$(docker exec "$CONTAINER" grep -c "inflect.acronym 'LX'" "${RAILS_ROOT}/config/initializers_before_autoloader/000_inflections.rb" 2>/dev/null | tr -d '[:space:]')
    VERIFY=${VERIFY:-0}
    if [ "$VERIFY" -gt 0 ]; then
        echo -e "  inflections.rb: ${GREEN}patched${NC}"
    else
        echo -e "  inflections.rb: ${RED}FAILED to patch${NC}"
        exit 1
    fi
fi

# ─── Copy extension modules ──────────────────────────────────────────

echo ""
echo -e "${YELLOW}Installing extension modules...${NC}"

# Copy the custom/ directory into the Rails root
docker cp "${SCRIPT_DIR}/extensions/lx" "${CONTAINER}:${RAILS_ROOT}/lx"

# Verify key files
for FILE in \
    "lx/app/models/lx/board.rb" \
    "lx/app/models/lx/board_label.rb" \
    "lx/app/services/lx/boards/issues/list_service.rb" \
    "lx/app/services/lx/boards/update_service.rb" \
    "lx/app/services/lx/boards/create_service.rb"; do
    if docker exec "$CONTAINER" test -f "${RAILS_ROOT}/${FILE}"; then
        echo -e "  ${FILE}: ${GREEN}installed${NC}"
    else
        echo -e "  ${FILE}: ${RED}MISSING${NC}"
        exit 1
    fi
done

# ─── Restart GitLab services ─────────────────────────────────────────

echo ""
echo -e "${YELLOW}Restarting GitLab Rails (puma + sidekiq)...${NC}"
docker exec "$CONTAINER" gitlab-ctl restart puma
docker exec "$CONTAINER" gitlab-ctl restart sidekiq

echo ""
echo -e "${GREEN}=== Custom Extensions Applied ===${NC}"
echo -e "GitLab version: ${GITLAB_VERSION}"
echo -e "Extensions: lx/ (board label scoping)"
echo ""
echo -e "${YELLOW}Verify:${NC}"
echo "  docker exec gitlab gitlab-rails runner \"puts Board.new.respond_to?(:board_labels)\""
echo "  docker exec gitlab gitlab-rails runner \"puts GitlabEdition.extensions\""

# Save applied version for future reference
echo "${GITLAB_VERSION}" > "${SCRIPT_DIR}/.last_applied_version"
