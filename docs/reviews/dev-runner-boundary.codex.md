---
source: codex
reviewed: 2026-08-16
context: dev-runner-boundary.md
---

# Security architecture review

(Verification table of external facts omitted here for brevity in this saved copy — codex verified all claims against Docker/GitLab/OCI documentation with sources; every fact row was marked "yes".)

## 1. Assessment of the draft

The draft is right about Option B as originally described and wrong about brokers categorically.

A root service that runs `cd developer-checkout && ./deploy.sh` or `docker compose -f developer-checkout/docker-compose.yml up` is not a boundary. It gives root authority to developer-controlled shell, Compose, Dockerfile, `.env`, `include`, `extends`, and file references. Docker's Compose trust guidance identifies these as privileged inputs.

But the stronger claim — "any small broker is ritual because it must validate arbitrary Compose" — is false. A real broker does not validate arbitrary Compose. It refuses to accept Compose at all.

The crucial distinction:
- A ritual broker delegates interpretation of developer-controlled infrastructure instructions.
- A genuine capability broker performs one administrator-defined state transition, with one narrowly typed developer input.

The draft also conflates three principals:

| Principal | Current authority | Can this host constrain it? |
|---|---|---|
| `websurfinmurf` human account | `sudo` and Docker group | No, not under the settled membership decision |
| CI job on runner 3 | General SSH key to that human account | No today; yes if that credential is removed or narrowed |
| Developer-built application image | Whatever its container configuration grants | Yes, materially, through administrator-owned container policy; residual kernel/shared-service risk remains |

Therefore point 4 needs narrowing. "The boundary is impossible" is correct against the human account. It is incorrect against CI-controlled repository content.

## 2. What I would do differently — corrected Option B (digest-only broker)

Contract: `deploy-networkingmanager(image = registry/...@sha256:<64 hex>)`. Nothing else supplied by CI: no repo path, no Compose path, no tag (no `latest`), no command/entrypoint/env-file/service/project overrides, no `deploy.sh` execution, no build on the deployment host.

Implementation properties:
1. **Administrator-owned policy** — deployment Compose file at e.g. `/etc/deploy-broker/networkingmanager/compose.yml`, developer cannot modify it.
2. **Digest-only artifact input** — Buildx `--metadata-file` → `containerimage.digest` passed as pipeline artifact. A digest provides immutability, not trust.
3. **Fixed container envelope** — privileged:false, no socket, no bind mounts, no devices, no host namespaces, cap_drop ALL, no-new-privileges, fixed nonzero user, read_only + tmpfs, CPU/mem/PID/log limits, only the two approved networks, only app-specific secrets, no host ports.
4. **Safe invocation** — exact argv, no shell, cleared environment, fixed workdir, default `.env` loading disabled: `docker compose --project-directory /etc/deploy-broker/networkingmanager -f .../compose.yml up -d --pull always --no-build --wait`.
5. **Socket authorization** — broker socket only mounted into runner 3, peer UID via SO_PEERCRED. Authenticates "runner 3", not a project/user — acceptable only because the requirement permits developers to affect each other; must be documented.
6. **No global cleanup verbs** — no down/prune/rm/network-delete/volume-delete/exec/inspect on caller-selected containers.
7. **Concurrency and audit** — per-service lock, full audit log, pull rate-limits; plus `resource_group: networkingmanager-production` in CI (GitLab deployments race by default).

That is a real boundary. Developer code still runs in a container with its intended capabilities, but cannot convert its Dockerfile into `/` mounted read-write or a privileged container.

## 3. SSH-as-target-user

Operationally valid but architecturally the wrong recommendation if the stated boundary matters. It adds no capability relative to runner 3's current state, but that is an indictment of the current state, not a reason to institutionalize it. Any eligible runner 3 job can ignore the proposed command and run `ssh websurfinmurf@localhost arbitrary-command` — the `.gitlab-ci.yml` command is not a restriction on the private key.

`ref_protected` is weaker than the draft says:
- Protected runners can optionally be enabled for MR pipelines (setting must be checked).
- A group Owner can edit a group runner's protected setting.
- An Owner inherits Maintainer permissions on protected branches.
- A manual job is not administrator approval; a user able to merge can run it and override variables.

Because websurfinmurf is Owner, this gate separates unprotected code from protected-ref code; it does not separate the developer from administrator resources.

If the immediate goal is to unblock deployment under the already-accepted "protected developer code is host-root-equivalent" risk, SSH is an honest temporary workaround. Label it exactly that. Do not claim it satisfies the developer-CI/admin boundary.

Interim alternative if broker deferred: administrator-owned deployment project with fixed CI definition (GitLab's own deployment-safety recommendation). Protected environments are Premium/Ultimate — not available on CE.

## 4. Concrete corrections for networkingmanager

The draft's "end-state refinement" is already half implemented: `.gitlab-ci.yml` already builds on runner 10 and pushes an image. But deployment ignores that artifact: build pushes `$CI_COMMIT_SHORT_SHA` + `latest`; `deploy.sh` runs `docker compose build` again on the production host; Compose file has both `image:` and `build:`; default deployed image is `latest`. The required change is to connect build output to deployment by digest and remove deployment-host building.

The suggested SSH command also has a correctness bug: `cd ~/projects/networkingmanager && ./deploy.sh` neither fetches nor checks out `$CI_COMMIT_SHA` — it deploys whatever is in the host checkout, stale or dirty. Deploying the pipeline's digest eliminates checkout ambiguity.

Migrations: bound to the same fixed digest, same restricted envelope, only the DB network, and a database role restricted to the intended database/schema.

## 5. Runner 7

`ref_protected` is meaningful mitigation but not a satisfactory final state — an Owner can change the protected setting, and it remains a root-equivalent endpoint for protected jobs. Retire after migrating ib-gateway; the blocker is two DIND jobs (`build` and `smoke`) in one project — small enough to treat retirement as active work, not a long-term accepted dependency. Removing runner 7 is insufficient if runner 3 retains unrestricted SSH-to-docker-user capability — the bypass audit must cover both.

## 6. Risks missed by both notes

- The broker is bypassed unless the SSH key is removed or restricted.
- Runner 3 is a shared identity — peer UID cannot prove which repo/ref/human initiated.
- Protected-runner configuration is controlled by the developer group Owner, not admin policy.
- Mutable tags and stale pipelines — use digest + deployment lock + outdated-deployment protection.
- Secret exfiltration is inherent — env file must contain only credentials the app is authorized to hold.
- Network attachment is a capability — a malicious image can probe everything on `networkingmanager-auth-net` and `postgres-net`; DB auth/ACLs/topology protect admin resources, not container naming.
- Resource DoS — fork/memory/log/pull floods need cgroup limits and rate controls.
- Migration damage is outside container isolation — define backup/forward-fix/rollback separately.
- Compose environment injection — root-owned compose is insufficient if the broker inherits attacker-controlled environment.
- Container escape remains residual risk — fixed unprivileged policy is a boundary, not proof against kernel exploits; separate infrastructure remains the structural answer for hostile-code resistance.

## Final verdict

Reject Option C for state-changing deployment (socket proxy POST sections are security-critical, no body validation). Reject Option B exactly as proposed (executes developer Compose/shell). Do not reject capability brokers generally — a digest-only broker backed by administrator-owned deployment policy genuinely constrains developer-controlled content and stays small because it removes Compose from the input language. Do not present SSH-as-websurfinmurf as satisfying the boundary — it is an expedient continuation of the current accepted root-equivalent CI model.

Revised honest position:
> The boundary is unachievable against the human developer while that account retains sudo and Docker access. It is achievable, with residual container/shared-service risk, against developer-controlled CI content by removing transitive host-root credentials and exposing only a fixed-policy deployment capability.
