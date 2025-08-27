#!/bin/bash
# Script to fix GitLab file ownership issues
# REQUIRES: sudo permissions

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== GitLab Permissions Fix ===${NC}"
echo ""
echo -e "${RED}This script requires sudo to fix ownership issues.${NC}"
echo -e "${YELLOW}Files in /home/administrator should never be owned by root!${NC}"
echo ""

DATA_DIR="/home/administrator/data/gitlab"

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo: sudo $0"
    exit 1
fi

echo -e "${YELLOW}Stopping GitLab if running...${NC}"
docker stop gitlab 2>/dev/null || true

echo -e "${YELLOW}Fixing ownership of GitLab files...${NC}"
chown -R administrator:administrators "$DATA_DIR"

echo -e "${YELLOW}Setting proper permissions...${NC}"
# Config files should be readable by owner/group
find "$DATA_DIR/config" -type f -name "*.key" -exec chmod 600 {} \;
find "$DATA_DIR/config" -type f -name "*.pub" -exec chmod 644 {} \;
chmod 600 "$DATA_DIR/config/gitlab-secrets.json" 2>/dev/null || true

echo -e "${GREEN}✓ Ownership fixed${NC}"
echo ""

echo -e "${YELLOW}Files are now owned by administrator:administrators${NC}"
ls -la "$DATA_DIR/config/" | head -5

echo ""
echo -e "${RED}Note: GitLab may recreate some files as root when it runs.${NC}"
echo -e "${YELLOW}This is a known issue with GitLab's Docker image.${NC}"
echo ""
echo "To prevent this in the future, consider:"
echo "1. Running GitLab with user namespace mapping"
echo "2. Using --user flag in docker run"
echo "3. Setting up a dedicated GitLab user with proper UID mapping"