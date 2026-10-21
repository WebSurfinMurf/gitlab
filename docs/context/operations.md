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

## CI Runner Topology (IDs are GitLab-side, via API)
- id 1 `linuxserver-administrator` — admin shell runner (administrators group).
- id 3 `developer linux server runner` — shell, tags `shell,linuxserver,developer`, **`ref_protected`** (2026-06-04; protected refs only). Dev SHELL deploys (njproperties, developer, minecraft), all `only:[main/master]`.
- id 7 `linuxserver-docker-dev` — docker executor, **`privileged=true` + mounts `/var/run/docker.sock`**, `run_untagged=true`, **`ref_protected`**. Was the dev dind builder; dev builds have MOVED to the build VM (id 10). ⚠️ **retire** once `developers/ib-gateway` build moves off it — the last remaining runner-7 job (2026-06-06).
- id 8 `cicd-runner` — docker, project-locked to `administrators/*` (NOT reachable by developer projects). NOTE: admin builds still use privileged dind runners here (`linuxserver-docker-admin`/`speckit-runner`, privileged+socket) — admin-tier build cleanup deferred.
- id 9 `linuxserver-dev-ci` — docker executor, **`privileged=false`, NO socket in job containers**, tag `dev-ci`, `run_untagged=false`. Non-privileged developer MR/test CI (2026-06-04).
- id 10 `linuxserver-build-vm` — **runs inside a dedicated KVM VM** (`gitlab-build-vm`, own kernel → userns ON), shell executor + Docker/**BuildKit**, tag `build`, `ref_protected`. The developer image-build node (2026-06-05). stocktrader + njproperties build here green. **No Kaniko/Buildah/dind** (host disables userns; the VM has its own kernel — see security.md).
- Admin GitLab API tokens: `GITLAB_ROOT_TOKEN`/`GITLAB_TOKEN_ADMIN`/`GL_TOKEN` in `secrets/gitlab.env` (NOT `GITLAB_TOKEN`).

## Runner config locations (interdependency — IMPORTANT)
- Runners **1/3/7** configs: `gitlab/runner/{name}/` (this tree).
- Runner **9 `dev-ci`** config + deploy: **`projects/cicd/runners/dev-ci/`** — deliberately OUTSIDE this hard-deny tree (a runner is a separate container that registers *to* GitLab, not part of the server; Review Board 2026-06-04 `projects/portainer/docs/reviews/lt7-runner-and-net.final.md`). **End-state: migrate ALL runners to `projects/cicd/runners/`.** If you inventory or redeploy runners, dev-ci is in `cicd`, not here.
- Runner **10 build VM**: VM provisioning + runner config in **`projects/cicd/build-node/`** — `host-prep.sh` (qemu/libvirt install, sudo), `create-vm.sh` (build the VM via Ubuntu 24.04 cloud image + cloud-init, sudo), `cloud-init/` (installs docker+buildx+gitlab-runner, self-registers runner 10). VM disk under `/var/lib/libvirt/images/`; runner token in `secrets/gitlab-runner-build-vm.env`. The VM (`gitlab-build-vm`) is managed via `virsh` (autostart on).

## Admin-tier CI deploy model (runner 1 `linuxserver-administrator` = `gitlab-runner-admin`)
- Jobs run **inside the runner container**: root, **host network**, host docker socket + `/home/administrator` bind-mounted → `./deploy.sh` drives the host docker daemon directly (no SSH-to-localhost).
- Standard admin pipeline shape: `validate → deploy → test → mirror` (mirror = `scripts/mirror-to-github.sh`, `allow_failure: true`).
- **Auto-deploy is safe only for idempotent `deploy.sh`** (`docker compose up -d [--remove-orphans]` — no-op when unchanged). Scripts that `docker compose down` first always bounce → gate `deploy` as `when: manual` (e.g. ibgateway).
- Compose project name defaults to the **CI checkout dir basename** (the GitLab project path's last segment). With an explicit `container_name:`, a name mismatch → "container name already in use". Pin `COMPOSE_PROJECT_NAME: <svc>` in CI `variables:` (postgres, portainer). Alt pattern: `cd /home/administrator/projects/<svc> && ./deploy.sh` from the canonical dir (keycloak).

## github→gitlab migration (admin services)
- [IMPLEMENTED] Tier 2 (9 repos) migrated 2026-06-07: traefik, grafana, promtail, keycloak, ibgateway, portainer, postgres, redis, bitwarden. Each: local `origin` → GitLab (github kept as backup mirror), runs from GitLab, deploys via pipeline (ibgateway deploy=manual). Tracked on `administrators/cicd` board (project id 18), cards #213–#221, enhancement `github-migration`.
- [IMPLEMENTED] Tier 1 `mcp` migrated 2026-06-07 (#208, in `review`): **clean "Option A" — fresh `git init`, NOT a full-history push**. GitHub repo was 104 MB / 16,305 tracked files (98% committed build artifacts) + 4 embedded third-party repos (gitlinks, no `.gitmodules` → empty on clone). Scrubbed to **282 files**: dropped `archive/`, vendored `matrix/server` (removed nested `.git`), added real root `.gitignore`. New repo `administrators/mcp` (id 71, **private**). GitHub push-mirror deliberately SKIPPED (fresh history would clobber GitHub's preserved old history → GitHub frozen as backup). Per-service `.gitlab-ci.yml` deferred (note: `dist/` now gitignored → CI must build it).
- [PLANNED] Tier 1 remaining (#209–#212: devscripts, aiclilistener, AICLIMenu, obsidianapi) — still backlog.
- Per-repo runbook: create GitLab project → push branches+tags → repoint `origin` → GitHub as push-mirror → add `.gitlab-ci.yml` → verify green. **Exception:** repos bloated with committed artifacts / embedded repos → use Option A (fresh history, no mirror), like mcp.
- Create a project via API: `glab api -X POST projects -f name=<n> -f path=<n> -f namespace_id=10 -f visibility=private -f description=...` (administrators group id = 10). Host push remote: `ssh://git@gitlab.ai-servicers.com:2222/administrators/<n>.git` (SSH key `~/.ssh/id_ed25519_gitlab`, port 2222).

## Docker host networking (affects CI — 2026-07-31 incident)
- `/etc/docker/daemon.json`: `default-address-pools [{base:10.4.0.0/16, size:29}]` → **every** network including the default bridge is a /29 (5 usable IPs). docker0 = 10.4.0.0/29.
- dev-ci runner (id 9) spawns short-lived *permission containers* on the default bridge per cache volume → long-lived squatters there starve CI (`no available IPv4 addresses`). `docker network prune` does NOT help (pool isn't exhausted, only docker0).
- [IMPLEMENTED] Squatters moved live 2026-07-31 (`docker network connect <net> <c> && docker network disconnect bridge <c>` — survives restart, NOT recreation): minecraft-jwog→minecraft_default, stocktrader-dev-db→stocktrader_default, traefik-preflight detached (orphan, restart=no). Only `gitlab-runner-dev-ci` remains on bridge.
- [PLANNED] Durable fix `"bip": "10.5.0.1/24"` scheduled Sat 2026-08-01 07:00 EDT via root systemd-run one-shot → `/home/administrator/scripts/apply-bip-maintenance.sh` (idempotent; aborts if CI job containers present; backs up + `dockerd --validate` before restart; log `/home/administrator/scripts/bip-maintenance-20260801.log`). Full daemon restart = all ~148 containers bounce.
- Rule: never `docker run` long-lived containers without `--network` — they land on the starved default bridge.

## Backup
- `docker exec -t gitlab gitlab-backup create`
- Stored in `/home/administrator/projects/backups/gitlab`
- 7-day retention

## Permission Fix
- `docker exec gitlab update-permissions && docker restart gitlab` for 502 errors
- GitLab uses internal UIDs (git=998, gitlab-psql=996, etc.)
