# Operations — GitLab Project

## Deployment
- Main: `./deploy.sh` (sources secrets, deploys container, sets up networks)
- Extensions: `cd custom-extensions && ./apply.sh` (after container start/upgrade)
- Runners: `cd runner/{user} && ./deploy.sh`

## Post-Upgrade Workflow
1. `./deploy.sh` — deploys new GitLab version
2. `cd custom-extensions && ./apply.sh` — re-applies LX patches (upgrade-safe verification)
3. `./verify.sh` — confirms extensions loaded
4. `./scope-board.sh` — re-scope boards if needed (board_labels persist in DB)

## Key Paths
- Project: `/home/administrator/projects/gitlab/`
- Data: `/home/administrator/data/gitlab/{config,logs,data}/`
- Extensions source: `custom-extensions/extensions/lx/`
- Container Rails root: `/opt/gitlab/embedded/service/gitlab-rails/`

## Container Details
- Name: `gitlab`
- Ports: 80 (HTTP), 2222 (SSH), 5050 (registry)
- Traefik routes: gitlab.ai-servicers.com, registry.gitlab.ai-servicers.com

## Backup
- `docker exec -t gitlab gitlab-backup create`
- Stored in `/home/administrator/projects/backups/gitlab`
- 7-day retention

## Permission Fix
- `docker exec gitlab update-permissions && docker restart gitlab` for 502 errors
- GitLab uses internal UIDs (git=998, gitlab-psql=996, etc.)
