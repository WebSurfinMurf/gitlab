#!/bin/bash
set -e

# GitLab Runner for Administrator Projects
# Only runs jobs for projects in the 'administrators' group

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTAINER_NAME="gitlab-runner-admin"
CONFIG_DIR="/home/administrator/projects/gitlab/runner/administrator/config"
GITLAB_URL="https://gitlab.ai-servicers.com"

echo -e "${GREEN}=== GitLab Runner (Administrator) Deployment ===${NC}"

# Load runner token from secrets
if [ -f "$HOME/projects/secrets/gitlab-runner-admin.env" ]; then
    source "$HOME/projects/secrets/gitlab-runner-admin.env"
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

# Stop and remove existing container
echo -e "${YELLOW}Stopping existing runner...${NC}"
docker kill $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Start gitlab-runner container
# Uses host network for DNS resolution to gitlab.ai-servicers.com
# Mounts administrator home for project file access
echo -e "${YELLOW}Starting GitLab Runner container...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    --restart always \
    --network host \
    -v "$CONFIG_DIR:/etc/gitlab-runner" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /home/administrator:/home/administrator \
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
    ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "gitlab-runner-admin"
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
echo -e "${YELLOW}SSH public key (add to administrator authorized_keys if not already):${NC}"
docker exec $CONTAINER_NAME cat /home/gitlab-runner/.ssh/id_ed25519.pub

# Check if already registered
if [ -f "$CONFIG_DIR/config.toml" ] && grep -q "token" "$CONFIG_DIR/config.toml"; then
    echo -e "${GREEN}Runner already registered${NC}"
else
    # Register the runner
    if [ -z "$GITLAB_RUNNER_TOKEN" ]; then
        echo -e "${RED}No runner token found!${NC}"
        echo "Create $HOME/projects/secrets/gitlab-runner-admin.env with:"
        echo "  GITLAB_RUNNER_TOKEN=glrt-xxx..."
        echo ""
        echo "Get token from GitLab Admin -> CI/CD -> Runners -> New group runner"
        echo "Select 'administrators' group, tags: shell,linuxserver,administrator"
        exit 1
    fi

    echo -e "${YELLOW}Registering runner...${NC}"
    docker exec $CONTAINER_NAME gitlab-runner register \
        --non-interactive \
        --url "$GITLAB_URL" \
        --token "$GITLAB_RUNNER_TOKEN" \
        --executor shell \
        --description "linuxserver-administrator"
fi

# Verify runner is working
echo -e "${YELLOW}Runner status:${NC}"
docker exec $CONTAINER_NAME gitlab-runner status || true

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "Container: ${GREEN}$CONTAINER_NAME${NC}"
echo -e "Config: ${GREEN}$CONFIG_DIR${NC}"
echo -e "Tags: ${GREEN}shell, linuxserver, administrator${NC}"
echo ""
echo -e "${YELLOW}This runner only executes jobs from the 'administrators' group${NC}"
