# GitLab CE Changelog

All notable changes to the GitLab CE deployment will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2025-08-27

### Added
- Initial GitLab CE deployment using Docker
- Keycloak SSO integration with OpenID Connect
- Container registry at registry.gitlab.ai-servicers.com
- SSH access on port 2222
- Automated backup configuration to /home/administrator/projects/backups/gitlab
- SendGrid SMTP relay for outbound email
- Resource limits (4GB RAM, 4 CPU cores)
- Traefik reverse proxy integration

### Configured
- Mixed URL strategy for OAuth (external HTTPS for browser, internal HTTP for backend)
- PostgreSQL with 256MB shared buffers
- Sidekiq with 15 concurrent workers  
- Puma with dynamic worker processes
- Container registry on port 5050
- Backup retention for 7 days
- America/New_York timezone

### Security
- Keycloak SSO with PKCE enabled
- Secrets externalized to environment file
- TLS certificates via Let's Encrypt
- Root password secured in secrets/gitlab.env

### Fixed
- Certificate resolver changed from "production" to "letsencrypt"
- OAuth token endpoint using internal keycloak:8080
- OAuth userinfo endpoint using internal keycloak:8080
- Network connectivity with --add-host for Keycloak resolution

### Scripts Created
- `deploy.sh` - Main deployment script
- `setup-keycloak.sh` - Configure Keycloak client
- `setup-runner.sh` - Add GitLab Runner
- `import-dashy.sh` - Import test project
- `fix-permissions.sh` - Fix file ownership

### Documentation
- Created CLAUDE.md with implementation details
- Created FIX-ROOT-OWNERSHIP.md for permission issues
- Added comprehensive inline documentation

### Known Issues
- GitLab container runs as root, creates root-owned files in user directory
- Puma occasionally restarts during high load
- Registry authentication sometimes requires re-login

## [Planned]

### Version 1.1.0
- [ ] Add GitLab Runner for CI/CD
- [ ] Configure GitHub mirroring
- [ ] Implement automated project imports
- [ ] Add Prometheus monitoring

### Version 1.2.0  
- [ ] Migrate to external PostgreSQL
- [ ] Implement S3-compatible object storage
- [ ] Add elasticsearch for advanced search
- [ ] Configure Pages for static sites

### Version 2.0.0
- [ ] High availability configuration
- [ ] Multiple application nodes
- [ ] Geo replication setup
- [ ] Kubernetes deployment option

## Migration Notes

### From Other Git Services
- GitHub: Use import tool or mirror repositories
- Bitbucket: Import via URL with access token
- Gitea: Direct repository import supported

### Upgrade Path
- Always backup before upgrading
- Review release notes for breaking changes
- Test in staging environment first
- Plan 30-60 minute maintenance window

---
*Format: [Semantic Versioning](https://semver.org/)*
*Maintainer: administrator@ai-servicers.com*