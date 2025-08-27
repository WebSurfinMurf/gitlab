#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GitLab Runner Setup ===${NC}"
echo ""

# Check if GitLab is ready
echo -e "${YELLOW}Checking if GitLab is ready...${NC}"
if ! docker logs gitlab 2>&1 | grep -q "gitlab Reconfigured!"; then
    echo -e "${RED}GitLab is not ready yet. Please wait for it to finish starting.${NC}"
    echo "Check with: docker logs gitlab | grep 'gitlab Reconfigured!'"
    exit 1
fi

echo -e "${GREEN}✓ GitLab is ready${NC}"
echo ""

# Check if runner exists
if docker ps -a | grep -q gitlab-runner; then
    echo -e "${YELLOW}Removing existing runner...${NC}"
    docker stop gitlab-runner 2>/dev/null || true
    docker rm gitlab-runner 2>/dev/null || true
fi

# Deploy GitLab Runner
echo -e "${YELLOW}Deploying GitLab Runner...${NC}"
docker run -d \
  --name gitlab-runner \
  --restart unless-stopped \
  --network gitlab-net \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/gitlab-runner:/etc/gitlab-runner \
  gitlab/gitlab-runner:latest

echo -e "${GREEN}✓ Runner container started${NC}"
echo ""

# Get registration token from GitLab
echo -e "${YELLOW}To register the runner, you need the registration token from GitLab:${NC}"
echo ""
echo "1. Login to GitLab: https://gitlab.ai-servicers.com"
echo "2. Go to Admin Area → CI/CD → Runners"
echo "3. Click 'New instance runner'"
echo "4. Copy the registration token"
echo ""
read -p "Enter the GitLab runner registration token: " RUNNER_TOKEN

if [ -z "$RUNNER_TOKEN" ]; then
    echo -e "${RED}No token provided. Exiting.${NC}"
    exit 1
fi

# Register the runner
echo -e "${YELLOW}Registering runner...${NC}"
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.ai-servicers.com" \
  --registration-token "$RUNNER_TOKEN" \
  --executor "docker" \
  --docker-image "docker:latest" \
  --description "Docker Runner" \
  --docker-privileged \
  --docker-network-mode "gitlab-net" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-volumes "/cache" \
  --tag-list "docker,linux" \
  --run-untagged="true" \
  --locked="false"

echo -e "${GREEN}✓ Runner registered successfully${NC}"
echo ""

# Verify runner status
echo -e "${YELLOW}Verifying runner status...${NC}"
docker exec -it gitlab-runner gitlab-runner status

echo ""
echo -e "${GREEN}=== GitLab Runner Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}The runner is now available for CI/CD pipelines!${NC}"
echo ""
echo "Runner capabilities:"
echo "- Docker-in-Docker support"
echo "- Can build and push Docker images"
echo "- Can deploy to local infrastructure"
echo "- Tagged with: docker, linux"
echo ""
echo "Test with a simple .gitlab-ci.yml:"
echo "---"
echo "test:"
echo "  script:"
echo "    - echo 'Hello from GitLab CI!'"
echo "    - docker version"