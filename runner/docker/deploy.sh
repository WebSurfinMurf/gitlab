#!/bin/bash
set -e

# GitLab Runner for Docker/DinD Builds (Shared)
# Runs docker build jobs for all projects

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTAINER_NAME="gitlab-runner-docker"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
GITLAB_URL="https://gitlab.ai-servicers.com"

echo -e "${GREEN}=== GitLab Runner (Docker/DinD) Deployment ===${NC}"

# Load runner token from secrets
SECRETS_FILE="/home/administrator/projects/secrets/gitlab-runner-docker.env"
if [ -f "$SECRETS_FILE" ]; then
    source "$SECRETS_FILE"
else
    echo -e "${RED}Secrets file not found: $SECRETS_FILE${NC}"
    exit 1
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

# Stop and remove existing container
echo -e "${YELLOW}Stopping existing runner...${NC}"
docker kill $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Start gitlab-runner container
# Uses host network for DNS resolution
# Mounts docker socket for DinD operations
echo -e "${YELLOW}Starting GitLab Runner container...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    --restart always \
    --network host \
    -v "$CONFIG_DIR:/etc/gitlab-runner" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gitlab/gitlab-runner:latest

echo -e "${YELLOW}Waiting for container to start...${NC}"
sleep 3

# Check if already registered
if [ -f "$CONFIG_DIR/config.toml" ] && grep -q "token" "$CONFIG_DIR/config.toml" 2>/dev/null; then
    echo -e "${GREEN}Runner already registered${NC}"
else
    # Register the runner
    if [ -z "$GITLAB_RUNNER_TOKEN" ]; then
        echo -e "${RED}No runner token found!${NC}"
        echo ""
        echo "To get a runner token:"
        echo "1. Go to GitLab -> Admin Area -> CI/CD -> Runners"
        echo "2. Click 'New instance runner'"
        echo "3. Set tags: docker"
        echo "4. Copy the token"
        echo ""
        echo "Create /home/administrator/projects/secrets/gitlab-runner-docker.env with:"
        echo "  GITLAB_RUNNER_TOKEN=glrt-xxx..."
        echo ""
        exit 1
    fi

    echo -e "${YELLOW}Registering runner...${NC}"
    docker exec $CONTAINER_NAME gitlab-runner register \
        --non-interactive \
        --url "$GITLAB_URL" \
        --token "$GITLAB_RUNNER_TOKEN" \
        --executor docker \
        --docker-image docker:24-dind \
        --docker-privileged \
        --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
        --description "linuxserver-docker"
fi

# Verify runner is working
echo -e "${YELLOW}Runner status:${NC}"
docker exec $CONTAINER_NAME gitlab-runner verify || true

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "Container: ${GREEN}$CONTAINER_NAME${NC}"
echo -e "Config: ${GREEN}$CONFIG_DIR${NC}"
echo -e "Tags: ${GREEN}docker${NC}"
echo -e "Executor: ${GREEN}docker (privileged)${NC}"
echo ""
echo -e "${YELLOW}This runner builds Docker images for CI/CD pipelines${NC}"
