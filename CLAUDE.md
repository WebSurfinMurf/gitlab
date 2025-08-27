# GitLab CE Deployment

## Overview
Self-hosted GitLab Community Edition with:
- Git repository management
- CI/CD pipelines
- Container registry
- Keycloak SSO integration
- GitHub mirroring for backup
- Automated deployments

## Architecture
```
GitLab CE → Traefik (HTTPS) → https://gitlab.ai-servicers.com
    ↓
Keycloak SSO ← Users
    ↓
GitLab Runner → Docker → Deploy to Infrastructure
    ↓
GitHub Mirror (backup)
```

## Key Features Configured

### 1. Repository Management
- Full Git hosting
- Merge requests & code review
- Branch protection
- Issue tracking
- Wiki documentation

### 2. CI/CD Pipelines
- Automated testing
- Configuration validation
- Auto-deployment on push
- Rollback on failure
- Docker-in-Docker support

### 3. GitHub Mirroring
- Automatic push to GitHub
- Backup of all repositories
- Maintains full history
- Can be scheduled or manual

### 4. Keycloak SSO
- Single sign-on with existing accounts
- Auto-provision users
- Group synchronization
- No separate passwords

## Deployment Workflow Example (Dashy)

```mermaid
graph LR
    A[Edit conf.yml] --> B[Git Push]
    B --> C[GitLab Pipeline]
    C --> D{Validate}
    D -->|Pass| E[Backup Current]
    D -->|Fail| F[Notify Error]
    E --> G[Deploy to Docker]
    G --> H[Rebuild Dashy]
    H --> I{Health Check}
    I -->|Healthy| J[Mirror to GitHub]
    I -->|Failed| K[Auto Rollback]
```

## Access URLs
- **GitLab**: https://gitlab.ai-servicers.com
- **Container Registry**: https://registry.gitlab.ai-servicers.com
- **SSH Git**: ssh://git@gitlab.ai-servicers.com:2222

## Deployment Scripts

### Initial Deployment
```bash
cd /home/administrator/projects/gitlab
./deploy.sh  # Sources secrets from /home/administrator/secrets/gitlab.env
```

### Available Scripts
- `deploy.sh` - Main deployment (reads config, deploys container, sets up networks)
- `setup-keycloak.sh` - Configure Keycloak SSO client (requires Keycloak admin password)
- `setup-runner.sh` - Register GitLab Runner for CI/CD
- `import-dashy.sh` - Import Dashy project with CI/CD pipeline

### Check GitLab Status
```bash
docker ps | grep gitlab
docker logs gitlab --tail 50
```

### Backup GitLab
```bash
docker exec -t gitlab gitlab-backup create
```

### Restore GitLab
```bash
docker exec -it gitlab gitlab-backup restore BACKUP=[backup_name]
```

## GitLab + Claude Code Workflow

### How Claude Code Benefits:
1. **Direct Git Operations**: I can commit changes directly to GitLab
2. **Pipeline Creation**: I write `.gitlab-ci.yml` for your projects
3. **Automated Testing**: Changes I make are validated before deployment
4. **Safe Rollbacks**: If my changes break something, auto-rollback
5. **Documentation**: Auto-generate docs from our sessions
6. **Version Control**: Track all changes we make together

### Example Workflow:
```yaml
Claude Code writes code → 
Commits to GitLab → 
Pipeline validates → 
Deploys to staging → 
Tests pass → 
Auto-deploy to production → 
Mirror to GitHub for backup
```

## Network Configuration
GitLab requires special network setup for Keycloak SSO:
- Container includes `--add-host keycloak.ai-servicers.com:172.22.0.3`
- Allows GitLab to reach Keycloak internally via HTTP while users use HTTPS
- Mixed URL strategy in OIDC config (external for browser, internal for API)

## Troubleshooting

### GitLab Won't Start
```bash
# Check logs
docker logs gitlab --tail 100

# Common issue: permissions
sudo chown -R 998:998 /home/administrator/projects/gitlab/data

# Reconfigure
docker exec -it gitlab gitlab-ctl reconfigure
```

### Runner Can't Connect
```bash
# Check runner status
docker exec -it gitlab-runner gitlab-runner status

# Re-register runner
docker exec -it gitlab-runner gitlab-runner register
```

### SSO Not Working
```bash
# Verify host entry exists
docker exec gitlab cat /etc/hosts | grep keycloak

# Test Keycloak connectivity from GitLab
docker exec gitlab curl -s http://keycloak.ai-servicers.com:8080/realms/master/.well-known/openid-configuration

# Check OAuth configuration
docker exec -it gitlab gitlab-rails console
> Gitlab::OAuth::Provider.providers
```

## Configuration & Secrets

### Environment Variables
Stored in `/home/administrator/secrets/gitlab.env`:
- `GITLAB_ROOT_PASSWORD`: Root user password (complex, no common words)
- `GITLAB_OIDC_CLIENT_SECRET`: Keycloak client secret (auto-generated)
- `GITLAB_SMTP_PASSWORD`: SendGrid API key for email
- All other GitLab settings and feature flags

### Data & Configuration Files
All GitLab data stored in `/home/administrator/data/gitlab/`:
- `config/` - GitLab configuration, SSL certificates, SSH keys
- `logs/` - Application logs
- `data/` - GitLab data, repositories, uploads
- Contains sensitive files like `gitlab-secrets.json` and SSH host keys

## Backup Strategy
- Daily automated backups via cron
- Stored in `/home/administrator/projects/backups/gitlab`
- Mirrored to GitHub for offsite backup
- 7-day retention policy

## Security Notes
- SSH on port 2222 (not default 22)
- Keycloak SSO for authentication
- Container registry requires authentication
- Private repositories by default
- Signed commits supported

## Known Issues

### File Ownership Problem
GitLab's Docker container runs as root internally and creates files owned by root in `/home/administrator/data/gitlab`. This is a security concern as files in user home directories should not be owned by root.

**To fix ownership:**
```bash
sudo /home/administrator/projects/gitlab/fix-permissions.sh
```

**Long-term solutions to consider:**
1. Use user namespace mapping in Docker
2. Run container with `--user` flag (may break GitLab)
3. Use a different GitLab image that supports non-root operation
4. Mount volumes with specific UID/GID options

---
*Deployed: 2025-08-26*
*Purpose: Central Git repository and CI/CD platform*