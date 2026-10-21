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

## CI Deploy Trust Boundary (LT-7, 2026-06-04)
- Single rootful docker daemon; any docker-capable identity is host-root-equivalent. Per `projects/portainer/docs/no-rootless.md`, per-network ACLs / socket-proxies are NOT boundaries here (rootless rejected). **docker-group-for-developers is accepted.**
- Real live-trading boundary = **IBKR account caps on `U15907310`** (only host-root-survivable control) + autonomous-agent containers having NO `docker.sock` + live IB on isolated `mcp-ib-live-net` (no host ports) + live deploy (`start.live.sh`) manual/admin-only.
- Developer CI by trust tier: tests → **id 9 `dev-ci`** (non-privileged, no socket); **builds → id 10 build VM** (BuildKit in a KVM VM); deploys → **id 3 shell** (`ref_protected`). **id 7** (privileged + socket) is `ref_protected` → no MR can reach it (pre-merge root-equivalent path closed); **retire** once `developers/ib-gateway` build moves to id 10 (last runner-7 job). Dev projects cannot reach admin privileged runners (id 8 project-locked).
- **Image builds run on the build VM (id 10), NOT on the host.** The host disables unprivileged user namespaces (hardening), which every rootless builder needs; the VM has its own kernel so plain Docker/BuildKit works while the host stays hardened and no privileged runner survives. **Kaniko AND Buildah were both evaluated and dropped** (Kaniko archived/orphaned — only a small community fork remains; Buildah needs userns). The VM is the architecturally-correct end-state — Review Board: `projects/portainer/docs/reviews/{kaniko-replacement-builder,daemonless-build-why-orphaned}.final.md`. A VM/daemonless builder here is hygiene (retire the privileged runner), not a live-trading boundary.
- **Dev dependency pinning (anti-drift):** dev apps pin the FULL transitive graph `==` (`requirements.in` → `pip-compile`/`uv pip compile --python-version <base>`, **no hashes**); Dockerfile installs the pinned `requirements.txt`. Range pins are insufficient (leave transitive deps loose — the actual drift cause). Full build/deploy model documented in the `gitlab-integration` skill.
