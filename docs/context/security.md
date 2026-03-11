# Security — GitLab Project

## Authentication
- Keycloak SSO via OIDC (`stocktrader` client)
- Hybrid endpoint config: browser=HTTPS, backend=HTTP (keycloak:8080 via keycloak-net)
- `discovery: false` required for hybrid config in gitlab.rb

## Secrets
- `$HOME/projects/secrets/gitlab.env` — root password, OIDC secret, SMTP key
- `$HOME/projects/secrets/gitlab-runner-{user}.env` — runner registration tokens
- SSH keys in `runner/{user}/config/` — NOT committed to repo (gitignored)

## Network Isolation
- gitlab-net: internal GitLab services
- keycloak-net: SSO backend communication
- traefik-net: HTTPS termination and routing

## Extension Security
- LX extensions run inside GitLab's Rails process (same trust level as GitLab itself)
- scope-board.sh uses direct SQL — input is CLI args only, not user-facing
- No new external attack surface added
