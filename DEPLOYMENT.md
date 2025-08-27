# GitLab CE Deployment Guide

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ or similar Linux
- **RAM**: Minimum 4GB, recommended 8GB
- **CPU**: 2+ cores, recommended 4 cores
- **Storage**: 50GB minimum for application and repositories
- **Docker**: Version 20.10+
- **Network**: Port 443, 2222 accessible

### Required Services
- **Traefik**: Reverse proxy (must be running)
- **Keycloak**: SSO provider (optional but configured)
- **PostgreSQL**: Can use internal or external
- **Redis**: Can use internal or external

## Initial Deployment

### 1. Prepare Environment

```bash
# Create project structure
mkdir -p /home/administrator/projects/gitlab
mkdir -p /home/administrator/projects/data/gitlab/{config,data,logs}
mkdir -p /home/administrator/projects/backups/gitlab
mkdir -p /home/administrator/secrets

# Set permissions
chmod 700 /home/administrator/secrets
```

### 2. Create Environment File

```bash
# Create secrets/gitlab.env
cat > /home/administrator/secrets/gitlab.env << 'EOF'
# GitLab Configuration
GITLAB_HOSTNAME=gitlab.ai-servicers.com
GITLAB_EXTERNAL_URL=https://gitlab.ai-servicers.com
GITLAB_SSH_PORT=2222

# Root Account
GITLAB_ROOT_EMAIL=administrator@ai-servicers.com
GITLAB_ROOT_PASSWORD=Secure#2025@Infrastructure$

# Email Configuration
GITLAB_SMTP_ENABLED=true
GITLAB_SMTP_ADDRESS=smtp.sendgrid.net
GITLAB_SMTP_PORT=587
GITLAB_SMTP_USER=apikey
GITLAB_SMTP_PASSWORD=your_sendgrid_api_key_here
GITLAB_SMTP_DOMAIN=ai-servicers.com
GITLAB_EMAIL_FROM=gitlab@ai-servicers.com
GITLAB_EMAIL_REPLY_TO=noreply@ai-servicers.com

# Container Registry
GITLAB_REGISTRY_ENABLED=true
GITLAB_REGISTRY_EXTERNAL_URL=https://registry.gitlab.ai-servicers.com
GITLAB_REGISTRY_PORT=5050

# Backup Configuration
GITLAB_BACKUP_PATH=/var/opt/gitlab/backups
GITLAB_BACKUP_KEEP_TIME=604800

# Resource Limits
GITLAB_MEMORY_LIMIT=4g
GITLAB_CPU_LIMIT=4

# Keycloak SSO (if using)
GITLAB_OIDC_ENABLED=true
GITLAB_OIDC_CLIENT_ID=gitlab
GITLAB_OIDC_CLIENT_SECRET=generated_by_keycloak
GITLAB_OIDC_ISSUER=https://keycloak.ai-servicers.com/realms/master
GITLAB_OIDC_REDIRECT_URI=https://gitlab.ai-servicers.com/users/auth/openid_connect/callback
EOF

chmod 600 /home/administrator/secrets/gitlab.env
```

### 3. Deploy GitLab

```bash
cd /home/administrator/projects/gitlab
./deploy.sh
```

### 4. Wait for Initialization

```bash
# Monitor startup (takes 5-10 minutes first time)
docker logs -f gitlab

# Check when ready
docker logs gitlab | grep 'gitlab Reconfigured!'

# Verify health
curl -I https://gitlab.ai-servicers.com/-/health
```

## Post-Deployment Configuration

### 1. Configure Keycloak SSO (Optional)

```bash
# Run setup script
./setup-keycloak.sh

# Or manually create client in Keycloak:
# - Client ID: gitlab
# - Client Protocol: openid-connect
# - Access Type: confidential
# - Valid Redirect URIs: https://gitlab.ai-servicers.com/*
# - Copy client secret to gitlab.env
```

### 2. Set Up GitLab Runner

```bash
# Deploy runner for CI/CD
./setup-runner.sh

# Register runner with GitLab
docker exec -it gitlab-runner gitlab-runner register \
  --url https://gitlab.ai-servicers.com \
  --registration-token YOUR_TOKEN \
  --executor docker \
  --docker-image alpine:latest
```

### 3. Configure Backup Automation

```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * docker exec -t gitlab gitlab-backup create CRON=1

# Clean old backups (keep 7 days)
0 3 * * * docker exec -t gitlab gitlab-backup create SKIP_BUILDS_ARTIFACTS=1
```

### 4. Initial Admin Tasks

```bash
# Access GitLab
firefox https://gitlab.ai-servicers.com

# Login as root
Username: root
Password: [from GITLAB_ROOT_PASSWORD]

# Configure via UI:
# - Admin Area → Settings → General → Sign-up restrictions
# - Admin Area → Settings → Network → Outbound requests
# - Admin Area → Settings → CI/CD → Continuous Integration
```

## Upgrade Deployment

### 1. Backup Current Installation

```bash
# Create backup
docker exec -t gitlab gitlab-backup create

# Backup configuration
cp -r /home/administrator/projects/data/gitlab/config /backup/gitlab-config-$(date +%Y%m%d)

# Backup secrets
cp /home/administrator/secrets/gitlab.env /backup/gitlab-env-$(date +%Y%m%d)
```

### 2. Pull New Image

```bash
# Check current version
docker exec gitlab cat /opt/gitlab/version-manifest.txt | head -1

# Pull latest image
docker pull gitlab/gitlab-ce:latest

# Or specific version
docker pull gitlab/gitlab-ce:16.0.0-ce.0
```

### 3. Deploy New Version

```bash
# Stop and remove old container
docker stop gitlab
docker rm gitlab

# Deploy new version
./deploy.sh

# Monitor upgrade
docker logs -f gitlab
```

### 4. Verify Upgrade

```bash
# Check version
docker exec gitlab gitlab-rake gitlab:env:info

# Run checks
docker exec gitlab gitlab-rake gitlab:check

# Test functionality
curl -I https://gitlab.ai-servicers.com
```

## Rollback Procedure

### If Upgrade Fails

```bash
# Stop failed container
docker stop gitlab
docker rm gitlab

# Deploy previous version
docker run -d \
  --name gitlab \
  --hostname gitlab.ai-servicers.com \
  gitlab/gitlab-ce:previous-version

# Restore from backup if needed
docker exec -it gitlab gitlab-backup restore BACKUP=timestamp
```

## Migration from Other Services

### From GitHub

```bash
# In GitLab UI:
# 1. New Project → Import Project → GitHub
# 2. Authenticate with GitHub token
# 3. Select repositories to import
# 4. Map users and permissions
```

### From Another GitLab

```bash
# On source GitLab
docker exec -t source-gitlab gitlab-backup create

# Copy backup to new server
scp backup.tar /home/administrator/projects/backups/gitlab/

# Restore on new GitLab
docker exec -it gitlab gitlab-backup restore BACKUP=backup_name
```

## Production Checklist

### Security
- [ ] Change root password from default
- [ ] Configure firewall rules
- [ ] Enable 2FA for admin accounts
- [ ] Set up fail2ban for SSH
- [ ] Configure rate limiting
- [ ] Review and restrict sign-up

### Performance
- [ ] Increase memory to 8GB if possible
- [ ] Configure swap space
- [ ] Enable Prometheus monitoring
- [ ] Set up log rotation
- [ ] Configure cache headers

### Backup & Recovery
- [ ] Test backup/restore procedure
- [ ] Set up automated backups
- [ ] Configure offsite backup storage
- [ ] Document recovery procedures
- [ ] Test disaster recovery

### Monitoring
- [ ] Set up health check monitoring
- [ ] Configure alerts for failures
- [ ] Monitor disk space usage
- [ ] Track memory/CPU usage
- [ ] Monitor backup success

## Maintenance Tasks

### Daily
- Check service health
- Monitor disk space
- Review error logs

### Weekly
- Test backup restoration
- Update container images
- Review security logs
- Check SSL certificate expiry

### Monthly
- Rotate secrets
- Clean old artifacts
- Update documentation
- Performance review

## Useful Commands

### Service Management
```bash
# Start/stop
docker start gitlab
docker stop gitlab

# Restart
docker restart gitlab

# View logs
docker logs gitlab -f --tail 100

# Execute commands
docker exec -it gitlab bash
```

### GitLab CLI Commands
```bash
# Reconfigure after config changes
docker exec gitlab gitlab-ctl reconfigure

# Check status
docker exec gitlab gitlab-ctl status

# Restart services
docker exec gitlab gitlab-ctl restart

# Run rake tasks
docker exec gitlab gitlab-rake [task]
```

### Troubleshooting
```bash
# Check configuration
docker exec gitlab gitlab-ctl show-config

# Run system check
docker exec gitlab gitlab-rake gitlab:check

# Clear cache
docker exec gitlab gitlab-rake cache:clear

# Database console
docker exec -it gitlab gitlab-psql
```

## Environment Variables

All configuration is driven by environment variables in `/home/administrator/secrets/gitlab.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| GITLAB_HOSTNAME | Public hostname | gitlab.ai-servicers.com |
| GITLAB_ROOT_PASSWORD | Initial root password | Complex password |
| GITLAB_SSH_PORT | SSH port on host | 2222 |
| GITLAB_MEMORY_LIMIT | Container memory | 4g |
| GITLAB_OIDC_ENABLED | Enable SSO | true/false |

## Network Requirements

### Firewall Rules
```bash
# Required ports
ufw allow 443/tcp  # HTTPS
ufw allow 2222/tcp # Git SSH
ufw allow 80/tcp   # HTTP redirect

# Internal only
# 5432 - PostgreSQL
# 6379 - Redis
# 8080 - Keycloak
```

### DNS Configuration
```
A record: gitlab.ai-servicers.com → server IP
A record: registry.gitlab.ai-servicers.com → server IP
```

## Support & Documentation

### Internal Resources
- This deployment guide
- `/home/administrator/projects/gitlab/TROUBLESHOOTING.md`
- `/home/administrator/projects/gitlab/ARCHITECTURE.md`

### External Resources
- Official Docs: https://docs.gitlab.com
- Docker Image: https://hub.docker.com/r/gitlab/gitlab-ce
- Community Forum: https://forum.gitlab.com

---
*Deployment Guide Version: 1.0*
*Last Updated: 2025-08-27*
*Maintained by: administrator@ai-servicers.com*