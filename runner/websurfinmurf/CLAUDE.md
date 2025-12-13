# GitLab Runner - WebSurfinMurf (Developer)

## Overview
GitLab Runner for executing CI/CD pipelines for websurfinmurf's projects.

**Container**: gitlab-runner-dev
**Executor**: shell
**Tags**: shell, linuxserver, developer
**User**: websurfinmurf

## Setup Instructions for WebSurfinMurf

### Prerequisites
1. You need access to GitLab at https://gitlab.ai-servicers.com
2. You need to be a member of a group or have projects to run CI/CD on
3. Docker access (you should already have this)

### Step 1: Create the Runner Token in GitLab

1. Log in to GitLab: https://gitlab.ai-servicers.com
2. Go to the group or project where you want the runner
3. Navigate to: **Settings → CI/CD → Runners**
4. Click **"New project runner"** or **"New group runner"**
5. Configure:
   - **Tags**: `shell, linuxserver, developer`
   - **Run untagged jobs**: No (unchecked)
   - **Description**: `linuxserver-websurfinmurf`
6. Click **Create runner**
7. Copy the runner authentication token (starts with `glrt-`)

### Step 2: Create the Secrets File

```bash
# Create secrets directory if it doesn't exist
mkdir -p ~/projects/secrets

# Create the runner env file
cat > ~/projects/secrets/gitlab-runner-dev.env << 'EOF'
# GitLab Runner Token for WebSurfinMurf Projects
# Get this token from GitLab -> Settings -> CI/CD -> Runners -> New runner
GITLAB_RUNNER_TOKEN=glrt-YOUR_TOKEN_HERE
EOF

# Secure the file
chmod 600 ~/projects/secrets/gitlab-runner-dev.env
```

Replace `glrt-YOUR_TOKEN_HERE` with your actual token from Step 1.

### Step 3: Copy Files to Your Home Directory

The runner files need to be in YOUR home directory:

```bash
# Create directory structure
mkdir -p ~/projects/gitlab/runner/websurfinmurf

# Copy from administrator's setup
cp /home/administrator/projects/gitlab/runner/websurfinmurf/deploy.sh \
   ~/projects/gitlab/runner/websurfinmurf/

cp /home/administrator/projects/gitlab/runner/websurfinmurf/CLAUDE.md \
   ~/projects/gitlab/runner/websurfinmurf/

# Make executable
chmod +x ~/projects/gitlab/runner/websurfinmurf/deploy.sh
```

### Step 4: Deploy the Runner

```bash
cd ~/projects/gitlab/runner/websurfinmurf
./deploy.sh
```

The script will:
1. Start the gitlab-runner-dev container
2. Generate an SSH key
3. Display the SSH public key
4. Register the runner with GitLab

### Step 5: Add SSH Key to Your Authorized Keys

The deploy script will print an SSH public key. Add it to your authorized_keys:

```bash
# The deploy script shows a key like:
# ssh-ed25519 AAAAC3NzaC1... gitlab-runner-dev

# Add it to your authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1..." >> ~/.ssh/authorized_keys
```

This allows the runner to SSH to localhost as your user to execute deploy scripts.

### Step 6: Verify the Runner

1. Check GitLab: Go to **Settings → CI/CD → Runners** - your runner should show as online
2. Test locally:
   ```bash
   docker exec gitlab-runner-dev gitlab-runner verify
   ```

## Using the Runner in Your Projects

### Example .gitlab-ci.yml

Create this file in your project root:

```yaml
stages:
  - deploy

variables:
  DEPLOY_PATH: /home/websurfinmurf/projects/YOUR_PROJECT

deploy:
  stage: deploy
  tags:
    - shell
    - linuxserver
    - developer
  only:
    - main
  script:
    - ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null websurfinmurf@localhost "cd $DEPLOY_PATH && git pull origin main && ./deploy.sh"
  environment:
    name: production
    url: https://your-app.ai-servicers.com
```

### How It Works

1. You push to main branch
2. GitLab sees `.gitlab-ci.yml` and triggers pipeline
3. Runner picks up job (matches tags)
4. Runner SSHs to localhost as websurfinmurf
5. Runs your deploy commands

## Troubleshooting

### Runner Not Picking Up Jobs
- Check tags match in `.gitlab-ci.yml` and runner config
- Verify runner is online: `docker exec gitlab-runner-dev gitlab-runner verify`
- Check runner logs: `docker logs gitlab-runner-dev --tail 50`

### SSH Permission Denied
- Verify SSH key is in `~/.ssh/authorized_keys`
- Test manually: `docker exec -u gitlab-runner gitlab-runner-dev ssh websurfinmurf@localhost whoami`

### Container Won't Start
- Check if port conflicts: `docker ps | grep runner`
- Check logs: `docker logs gitlab-runner-dev`

### Re-register Runner
```bash
# If token expired or need to re-register
docker exec gitlab-runner-dev gitlab-runner unregister --all-runners
rm -rf ~/projects/gitlab/runner/websurfinmurf/config/*
./deploy.sh
```

## Files

```
~/projects/
├── secrets/
│   └── gitlab-runner-dev.env    # Runner token (create this)
└── gitlab/
    └── runner/
        └── websurfinmurf/
            ├── deploy.sh        # Deployment script
            ├── config/          # Runner config (auto-created)
            └── CLAUDE.md        # This file
```

## Differences from Administrator Runner

| Aspect | Administrator | WebSurfinMurf |
|--------|--------------|---------------|
| Container | gitlab-runner-admin | gitlab-runner-dev |
| Tags | administrator | developer |
| Home mount | /home/administrator | /home/websurfinmurf |
| SSH target | administrator@localhost | websurfinmurf@localhost |
| Scope | administrators group | your projects/groups |

---
*Created: 2025-12-13*
