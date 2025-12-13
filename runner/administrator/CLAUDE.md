# GitLab Runner - Administrator

## Overview
GitLab Runner for executing CI/CD pipelines for projects in the `administrators` group.

**Container**: gitlab-runner-admin
**Executor**: shell
**Tags**: shell, linuxserver, administrator
**Scope**: administrators group only (group ID: 10)

## User Structure
This server has two users with separate runners:
- **administrator** - This runner (gitlab-runner-admin)
- **websurfinmurf** - Separate runner needed (gitlab-runner-dev) - not yet created

## Deployment

```bash
cd /home/administrator/projects/gitlab/runner/administrator
./deploy.sh
```

## Configuration

**Secrets**: `$HOME/projects/secrets/gitlab-runner-admin.env`
```bash
GITLAB_RUNNER_TOKEN=glrt-xxx...
```

**Config**: `/home/administrator/projects/gitlab/runner/administrator/config/config.toml`

## How CI/CD Works

1. Push to a project in `administrators` group (e.g., dashy)
2. GitLab sees `.gitlab-ci.yml` in the repo
3. GitLab assigns job to runner with matching tags
4. Runner executes the job in the shell (as container user)
5. Job has access to `/home/administrator` via volume mount

## Projects Using This Runner

| Project | Repo | Auto-Deploy |
|---------|------|-------------|
| dashy | administrators/dashy | Yes - runs deploy.sh on push |

## Adding New Projects

1. Create `.gitlab-ci.yml` in the project with tags: `shell`, `linuxserver`, `administrator`
2. Push to GitLab
3. Pipeline will auto-trigger

Example `.gitlab-ci.yml`:
```yaml
stages:
  - deploy

deploy:
  stage: deploy
  tags:
    - shell
    - linuxserver
    - administrator
  only:
    - main
  script:
    - cd /home/administrator/projects/YOUR_PROJECT
    - git pull origin main
    - ./deploy.sh
```

## Troubleshooting

```bash
# Check runner status
docker exec gitlab-runner-admin gitlab-runner status

# View runner logs
docker logs gitlab-runner-admin --tail 50

# Re-register runner (if token expired)
docker exec gitlab-runner-admin gitlab-runner unregister --all-runners
./deploy.sh

# Verify runner in GitLab
# Go to: GitLab Admin -> CI/CD -> Runners
```

## Security Notes

- Runner only executes jobs from `administrators` group
- Shell executor runs commands directly (not in Docker)
- Has access to `/home/administrator` filesystem
- Uses `run_untagged=false` - only runs tagged jobs

---
*Created: 2025-12-13*
