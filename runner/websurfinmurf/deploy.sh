#!/bin/bash
set -e

# GitLab Runner for WebSurfinMurf (Developer) Projects
# Runs jobs for projects accessible to websurfinmurf user

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTAINER_NAME="gitlab-runner-dev"
CONFIG_DIR="/home/websurfinmurf/projects/gitlab/runner/websurfinmurf/config"
GITLAB_URL="https://gitlab.ai-servicers.com"

echo -e "${GREEN}=== GitLab Runner (WebSurfinMurf/Developer) Deployment ===${NC}"

# Load runner token from secrets
if [ -f "$HOME/projects/secrets/gitlab-runner-dev.env" ]; then
    source "$HOME/projects/secrets/gitlab-runner-dev.env"
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

# Stop and remove existing container
echo -e "${YELLOW}Stopping existing runner...${NC}"
docker kill $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Start gitlab-runner container
# Uses host network for DNS resolution to gitlab.ai-servicers.com
# Mounts websurfinmurf home for project file access
echo -e "${YELLOW}Starting GitLab Runner container...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    --restart always \
    --network host \
    -v "$CONFIG_DIR:/etc/gitlab-runner" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/websurfinmurf:/home/websurfinmurf \
    gitlab/gitlab-runner:latest

echo -e "${YELLOW}Waiting for container to start...${NC}"
sleep 3

# Configure SSH for localhost connections (needed for CI/CD jobs)
# Shell executor runs as gitlab-runner user, so set up SSH for that user
echo -e "${YELLOW}Configuring SSH for CI/CD...${NC}"
docker exec $CONTAINER_NAME sh -c '
# Generate SSH key for root if needed
mkdir -p /root/.ssh
if [ ! -f /root/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "gitlab-runner-dev"
fi

# Set up gitlab-runner user SSH (shell executor runs as this user)
mkdir -p /home/gitlab-runner/.ssh
cp /root/.ssh/id_ed25519* /home/gitlab-runner/.ssh/
cat > /home/gitlab-runner/.ssh/config << EOF
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.ssh
chmod 700 /home/gitlab-runner/.ssh
chmod 600 /home/gitlab-runner/.ssh/*
'

# Show public key for adding to authorized_keys
echo -e "${YELLOW}SSH public key (add to websurfinmurf authorized_keys):${NC}"
docker exec $CONTAINER_NAME cat /home/gitlab-runner/.ssh/id_ed25519.pub

# Check if already registered
if [ -f "$CONFIG_DIR/config.toml" ] && grep -q "token" "$CONFIG_DIR/config.toml"; then
    echo -e "${GREEN}Runner already registered${NC}"
else
    # Register the runner
    if [ -z "$GITLAB_RUNNER_TOKEN" ]; then
        echo -e "${RED}No runner token found!${NC}"
        echo ""
        echo "To get a runner token:"
        echo "1. Go to GitLab -> Admin Area -> CI/CD -> Runners"
        echo "2. Click 'New instance runner' or 'New group runner'"
        echo "3. Select scope (group or project)"
        echo "4. Set tags: shell, linuxserver, developer"
        echo "5. Copy the token"
        echo ""
        echo "Create $HOME/projects/secrets/gitlab-runner-dev.env with:"
        echo "  GITLAB_RUNNER_TOKEN=glrt-xxx..."
        echo ""
        exit 1
    fi

    echo -e "${YELLOW}Registering runner...${NC}"
    docker exec $CONTAINER_NAME gitlab-runner register \
        --non-interactive \
        --url "$GITLAB_URL" \
        --token "$GITLAB_RUNNER_TOKEN" \
        --executor shell \
        --description "linuxserver-websurfinmurf"
fi

# Verify runner is working
echo -e "${YELLOW}Runner status:${NC}"
docker exec $CONTAINER_NAME gitlab-runner verify || true

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "Container: ${GREEN}$CONTAINER_NAME${NC}"
echo -e "Config: ${GREEN}$CONFIG_DIR${NC}"
echo -e "Tags: ${GREEN}shell, linuxserver, developer${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Add the SSH public key above to ~/.ssh/authorized_keys${NC}"
echo -e "${YELLOW}This runner executes jobs as websurfinmurf user via SSH${NC}"
