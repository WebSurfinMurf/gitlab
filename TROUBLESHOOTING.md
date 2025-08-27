# GitLab CE Troubleshooting Guide

## Common Issues and Solutions

### 1. GitLab Returns 404 Error

#### Symptoms
- https://gitlab.ai-servicers.com returns "404 page not found"
- Container is running but not accessible

#### Diagnosis
```bash
# Check if GitLab is responding internally
curl -I http://$(docker inspect gitlab -f '{{.NetworkSettings.Networks.traefik-proxy.IPAddress}}'):80

# Check Traefik routing
docker logs traefik | grep gitlab

# Verify labels
docker inspect gitlab | grep -A 20 Labels
```

#### Solution
```bash
# Fix certificate resolver
docker stop gitlab && docker rm gitlab
# Edit deploy.sh: change "production" to "letsencrypt"
./deploy.sh

# Verify Traefik network
docker network connect traefik-proxy gitlab
```

### 2. Keycloak SSO Login Fails

#### Symptoms
- "Could not authenticate you from OpenIDConnect"
- SSL connect errors
- Invalid issuer errors

#### Diagnosis
```bash
# Test Keycloak connectivity from GitLab
docker exec gitlab curl -s http://keycloak:8080/realms/master/.well-known/openid-configuration

# Check OAuth configuration
docker exec gitlab grep -A 30 omniauth /etc/gitlab/gitlab.rb

# Verify host resolution
docker exec gitlab ping keycloak.ai-servicers.com
```

#### Solution
```ruby
# Edit /home/administrator/projects/data/gitlab/config/gitlab.rb
# Use mixed URLs - external for browser, internal for backend:
gitlab_rails['omniauth_providers'] = [
  {
    args: {
      issuer: "https://keycloak.ai-servicers.com/realms/master",
      discovery: false,
      pkce: true,
      client_options: {
        authorization_endpoint: "https://keycloak.ai-servicers.com/realms/master/protocol/openid-connect/auth",
        token_endpoint: "http://keycloak:8080/realms/master/protocol/openid-connect/token",
        userinfo_endpoint: "http://keycloak:8080/realms/master/protocol/openid-connect/userinfo",
        jwks_uri: "http://keycloak:8080/realms/master/protocol/openid-connect/certs"
      }
    }
  }
]

# Reconfigure GitLab
docker exec gitlab gitlab-ctl reconfigure
```

### 3. GitLab Container Won't Start

#### Symptoms
- Container exits immediately
- Container restart loop

#### Diagnosis
```bash
# Check container logs
docker logs gitlab --tail 100

# Check for port conflicts
netstat -tlnp | grep -E ":(80|22|5050)"

# Verify volume permissions
ls -la /home/administrator/projects/data/gitlab/
```

#### Solution
```bash
# Fix permissions
sudo chown -R 998:998 /home/administrator/projects/data/gitlab/data

# Remove stale container
docker rm -f gitlab

# Redeploy
./deploy.sh
```

### 4. Puma (Web Server) Returns 502

#### Symptoms
- "502 Bad Gateway" errors
- GitLab UI not loading

#### Diagnosis
```bash
# Check Puma status
docker exec gitlab gitlab-ctl status puma

# View Puma logs
docker exec gitlab tail -50 /var/log/gitlab/puma/puma_stderr.log

# Check memory usage
docker stats gitlab --no-stream
```

#### Solution
```bash
# Restart Puma
docker exec gitlab gitlab-ctl restart puma

# If memory issues, restart container
docker restart gitlab

# Increase memory limit if needed
# Edit deploy.sh: --memory="6g"
```

### 5. Git Push/Clone Fails

#### Symptoms
- "Connection refused" on port 2222
- Authentication failures
- Timeout errors

#### Diagnosis
```bash
# Test SSH connectivity
ssh -T git@gitlab.ai-servicers.com -p 2222

# Check SSH service
docker exec gitlab gitlab-ctl status sshd

# Verify port mapping
docker port gitlab 22
```

#### Solution
```bash
# Add SSH key to GitLab
cat ~/.ssh/id_rsa.pub
# Add via GitLab UI: User Settings → SSH Keys

# Fix SSH config
cat >> ~/.ssh/config << EOF
Host gitlab.ai-servicers.com
  Port 2222
  User git
EOF

# For HTTPS, create personal access token
# GitLab UI: User Settings → Access Tokens
```

### 6. Container Registry Issues

#### Symptoms
- Can't push Docker images
- Registry authentication fails

#### Diagnosis
```bash
# Test registry endpoint
curl -I https://registry.gitlab.ai-servicers.com

# Check registry logs
docker exec gitlab tail -50 /var/log/gitlab/registry/current

# Verify configuration
docker exec gitlab grep -A 10 registry /etc/gitlab/gitlab.rb
```

#### Solution
```bash
# Docker login to registry
docker login registry.gitlab.ai-servicers.com
# Username: your-gitlab-username
# Password: personal-access-token

# If using CI/CD
# Use $CI_REGISTRY_USER and $CI_REGISTRY_PASSWORD variables
```

### 7. Email Not Sending

#### Symptoms
- No confirmation emails
- No notification emails

#### Diagnosis
```bash
# Check SMTP configuration
docker exec gitlab grep -A 10 smtp /etc/gitlab/gitlab.rb

# Test email sending
docker exec gitlab gitlab-rails console
> Notify.test_email('test@example.com', 'Test', 'Test message').deliver_now

# Check mail logs
docker exec gitlab tail -50 /var/log/gitlab/gitlab-rails/production.log | grep -i mail
```

#### Solution
```bash
# Update SendGrid API key in secrets/gitlab.env
GITLAB_SMTP_PASSWORD=your_sendgrid_api_key

# Redeploy
./deploy.sh

# Or update directly
docker exec gitlab gitlab-rails console
> ActionMailer::Base.smtp_settings[:password] = 'new_api_key'
```

### 8. High Memory Usage

#### Symptoms
- Container using > 4GB RAM
- System becoming slow
- OOM kills

#### Diagnosis
```bash
# Check current usage
docker stats gitlab

# Identify memory consumers
docker exec gitlab ps aux --sort=-%mem | head

# Check Sidekiq jobs
docker exec gitlab gitlab-rails console
> Sidekiq::Queue.all.map(&:size)
```

#### Solution
```bash
# Reduce worker counts
# Edit gitlab.rb:
sidekiq['max_concurrency'] = 10
puma['worker_processes'] = 2

# Reconfigure
docker exec gitlab gitlab-ctl reconfigure

# Clear cache if needed
docker exec gitlab gitlab-rake cache:clear
```

### 9. Backup/Restore Failures

#### Symptoms
- Backup task fails
- Restore incomplete

#### Diagnosis
```bash
# Check backup directory
ls -la /home/administrator/projects/backups/gitlab/

# View backup logs
docker exec gitlab tail -50 /var/log/gitlab/gitlab-rails/production.log | grep -i backup

# Check disk space
df -h /home/administrator/projects/backups/
```

#### Solution
```bash
# Manual backup
docker exec -t gitlab gitlab-backup create

# Restore specific backup
docker exec -it gitlab gitlab-backup restore BACKUP=1234567890_2025_08_27_16.0.0

# Fix permissions after restore
docker exec gitlab gitlab-ctl reconfigure
docker restart gitlab
```

### 10. File Ownership Issues

#### Symptoms
- Files owned by root in user directory
- Permission denied errors

#### Diagnosis
```bash
# Check file ownership
ls -la /home/administrator/projects/data/gitlab/

# Identify root-owned files
find /home/administrator/projects/data/gitlab -user root -ls
```

#### Solution
```bash
# Temporary fix
sudo chown -R administrator:administrators /home/administrator/projects/data/gitlab/

# Permanent solutions documented in FIX-ROOT-OWNERSHIP.md
# Consider: Docker user namespace remapping or Podman
```

## Diagnostic Commands Reference

### Container Health
```bash
docker inspect gitlab --format='{{.State.Health.Status}}'
docker exec gitlab gitlab-ctl status
docker exec gitlab gitlab-rake gitlab:check
```

### Service Logs
```bash
# All logs
docker logs gitlab -f

# Specific service
docker exec gitlab gitlab-ctl tail puma
docker exec gitlab gitlab-ctl tail sidekiq
docker exec gitlab gitlab-ctl tail gitaly
```

### Configuration
```bash
# Show current config
docker exec gitlab gitlab-ctl show-config

# Reconfigure after changes
docker exec gitlab gitlab-ctl reconfigure

# Restart all services
docker exec gitlab gitlab-ctl restart
```

### Database
```bash
# Rails console
docker exec -it gitlab gitlab-rails console

# Database console
docker exec -it gitlab gitlab-psql

# Run migrations
docker exec gitlab gitlab-rake db:migrate
```

## Performance Tuning

### Quick Wins
1. Increase memory limit to 6-8GB
2. Use external PostgreSQL
3. Use external Redis
4. Enable Prometheus monitoring
5. Configure swap space

### Advanced Optimization
1. Separate Gitaly server
2. Object storage for artifacts
3. CDN for static assets
4. Elasticsearch for search
5. Multiple Sidekiq processes

## Getting Help

### Resources
- GitLab Docs: https://docs.gitlab.com
- Container Logs: `docker logs gitlab`
- System Status: `docker exec gitlab gitlab-ctl status`
- Health Check: https://gitlab.ai-servicers.com/-/health

### Support Channels
- Internal: administrator@ai-servicers.com
- GitLab Forum: https://forum.gitlab.com
- GitLab Issues: Create issue with logs

---
*Last Updated: 2025-08-27*
*Version: 1.0*