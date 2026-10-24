# Security — GitLab Project

## Authentication
- Keycloak SSO via OIDC (`stocktrader` client)
- Hybrid endpoint config: browser=HTTPS, backend=HTTP (keycloak:8080 via keycloak-net)
- `discovery: false` required for hybrid config in gitlab.rb

## Secrets
- `$HOME/projects/secrets/gitlab.env` — root password, OIDC secret, SMTP key; `GITLAB_TOKEN_ADMIN` for API writes (ROOT token 403s on retries)
- `$HOME/projects/secrets/gitlab-runner-{user}.env` — runner registration tokens
- [IMPLEMENTED] `.gitignore` blocks `runner/*/config/ssh_key*`, `runner/*/config/config.toml` (live glrt tokens), agents-runtime-host state
- [OPEN] `runner/administrator/config/config.toml` is tracked with live glrt tokens; repo remote is **github.com (WebSurfinMurf/gitlab)** → tokens in offsite history. Fix = `git rm --cached` + rotate (re-register runner). SSH keys also still on disk under `runner/*/config/` — relocate to secrets pattern.

## Least-Privilege Accounts (pattern, 2026-10-20)
- Keycloak user (master realm) + GitLab identity: provider `openid_connect`, **extern_uid = username** (not UUID)
- GitLab **External flag is load-bearing**: hides internal-visibility projects (5 exist) from the user
- Grant scope via GitLab group membership / project **group share** (`POST /projects/:id/share`), never per-user where a group exists
- Example: `wdylanbibb` (GitLab id 10, External) — Reporter on `claude-skills`; GitLab group `devops` (id 114) shared into `administrators/gitlab` (project 15) at Reporter
- **CE has no OIDC group sync** → Keycloak `/devops` and GitLab `devops` are parallel registries; new member = add in BOTH
- Keycloak master realm password policy: `length(8) + upperCase(1) + lowerCase(1) + digits(1) + specialChars(1)` — API user-create 400s are usually policy rejections

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
