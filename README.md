# GitLab CE Deployment

## Essential Scripts
- `deploy.sh` - Main deployment script (uses secrets from /home/administrator/secrets/gitlab.env)
- `setup-keycloak.sh` - Configure Keycloak SSO integration
- `setup-runner.sh` - Set up GitLab CI/CD runner
- `import-dashy.sh` - Import Dashy project with CI/CD pipeline
- `fix-permissions.sh` - Host-side permission fixes (rarely needed)

## Documentation
- `CLAUDE.md` - Main documentation with troubleshooting
- `DEPLOYMENT.md` - Detailed deployment guide
- `ARCHITECTURE.md` - System architecture overview
- `TROUBLESHOOTING.md` - General troubleshooting guide
- `TROUBLESHOOTING-502.md` - Specific 502 error fixes
- `FIX-ROOT-OWNERSHIP.md` - Root ownership issue documentation
- `CHANGELOG.md` - Change history

## Quick Fix for 502 Errors
```bash
docker exec gitlab update-permissions
docker restart gitlab
```

## Access
- GitLab: https://gitlab.ai-servicers.com
- Registry: https://registry.gitlab.ai-servicers.com
- SSH: Port 2222

---
*Project created on Tue Aug 26 09:48:54 PM EDT 2025*