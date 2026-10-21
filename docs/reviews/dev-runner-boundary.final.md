---
name: dev-runner-boundary
created: 2026-08-16
status: review-complete
sources: [gemini, codex, claude]
---

# Developer CI deploy boundary — Review Board synthesis

Reviewing websurfinmurf's note (`/mnt/shared/aichat/websurfinmurf.developer-runner-restrictions.md`) against the settled LT-7 model, with a draft position that the Board was asked to attack.

## Consensus (three-way — highest confidence)

1. **The requested boundary is unenforceable against websurfinmurf-the-human** on this host while he holds `docker` + `sudo` group membership. LT-7's verdict stands there; no CI mechanism changes it. All three reviewers endorse saying this plainly.
2. **The draft's "any broker is a ritual" generalization is WRONG.** All three independently converged on the same correct broker design (call it **B2 / digest-only broker**): the broker never reads developer-controlled compose/Dockerfile/shell at all. Admin-owned, root-owned compose file per allow-listed project (e.g. `/etc/deploy-broker/networkingmanager/compose.yml`) pins networks/volumes/limits/privileges; the developer's pipeline builds on runner 10 and pushes to the registry; the broker takes exactly one narrowly-typed input — `deploy <project> <sha256:64-hex-digest>` — substitutes it into the admin's file, and runs `compose pull && up -d --no-build --wait`. Pod-spec authority never leaves root's hands, so there is no validator to grow. websurfinmurf's B-as-written (broker runs repo `deploy.sh`) IS a ritual — concede nothing there — but B2 is a genuine CI-path boundary at ~100-line scale.
3. **Option C (socket proxy) rejected** — filters by API endpoint section, never inspects request bodies, cannot block `privileged:true`/bind mounts inside a create call even in principle. (Verified current: tecnativa v0.5.0, maintained — rejected for fit, not staleness.)
4. **`ref_protected` is not a boundary against websurfinmurf** — he is Owner of the developers group, can protect any branch and (as Owner) alter runner protection settings. It gates the MR/fork/junior-dev path only.
5. **The runner-3 SSH key is the headline finding.** `/home/gitlab-runner/.ssh/id_ed25519` → `websurfinmurf@localhost` works non-interactively, so EVERY runner-3 job on a protected ref already holds full websurfinmurf identity (docker group = host-root-equivalent), deploy job or not. Compromise of runner 3 exfiltrates a key that grants persistent host root. **The SSH deploy pattern and any broker are mutually exclusive** — a broker with the key still present is theater.

## Key insights

- (Codex) networkingmanager **already builds on runner 10 and pushes an image** — but `deploy.sh` rebuilds on the production host and deploys mutable `latest`. The real gap is connecting pipeline output to deployment **by digest**, and removing deployment-host builds. Also: `cd ~/projects/networkingmanager && ./deploy.sh` over SSH deploys whatever is in the checkout (stale/dirty) — digest deploys eliminate that too.
- (Claude) **The no-rootless VM rejection does not transfer here** — no-rootless.md killed VMs for protecting live *from an actor already holding the rootful socket*; this problem is protecting the host *from a workload*, exactly the direction VM isolation binds. A **same-host KVM guest for dev workloads** (the runner-10 pattern, applied to deploys) closes websurfinmurf's stated requirement with a kernel boundary, no broker, no compose-ownership friction. "Separate host is the only structural close" is false.
- (Claude) **Single-developer tripwire**: every conclusion is load-bearing on "exactly one, trusted developer." The day a second developer gets Maintainer on any developers project, the SSH pattern hands them websurfinmurf's host-root-equivalent identity and this decision reopens. Record it.
- (Gemini) If the SSH pattern is kept, the key must be narrowed: `command="..."` forced-command restriction in websurfinmurf's `authorized_keys`, not a full shell.
- (Codex/Claude) Honest reframing of "unachievable": *unachievable against the human account (settled, accepted); achievable against developer-controlled CI content — by removing transitive host-root credentials (the SSH key), retiring runner 7, and exposing only a fixed-policy deploy capability.*

## Disagreements

- **Is B2 worth building?** Gemini: no — hardening CI against a user who can `sudo` interactively is security theater; advise against. Codex: yes — it's the correct end-state; SSH is an "expedient continuation of the accepted root-equivalent model" and should be labeled a workaround. Claude: it's a genuine choice that turns on which threat you care about (compromised token / malicious dependency / developer #2 — real and cheap to close) — decision belongs to the administrator, and whoever owns the boundary must author it (not the constrained party).
- **My assessment**: Codex/Claude have the better argument *if* the CI-path threat model matters to the operator; Gemini is right that against the human it changes nothing. This is exactly the accepted-risk posture question LT-7 settled for docker-group — reopening it is the human administrator's call, not mine.

## Action items (ordered)

1. **Human decision required — pick the CI-deploy end-state**:
   - (a) *No CI boundary, stated plainly*: SSH-as-websurfinmurf on runner 3 (documented architecture), labeled an explicit acceptance that protected-ref dev CI = host-root-equivalent. If chosen: add `command=` forced-command restriction + digest-based deploys.
   - (b) *B2 digest-only broker*: admin-authored compose in `/etc/deploy-broker/`, remove the SSH key from runner 3, deploy verb only. Genuine CI boundary; admin owns pod-spec changes.
   - (c) *Dev-workloads KVM VM*: developers get full docker freedom inside a guest; Traefik routes to VM IP. Strongest close of websurfinmurf's stated requirement short of new hardware.
2. **Runner 7**: treat retirement as active work, not accepted dependency. websurfinmurf migrates ib-gateway's `build` + `smoke` jobs off untagged dind (runner 10, tag `build` — shell executor, ignores `image:`/`services:`, rewrite to plain buildx per stocktrader pattern) → administrator retires runner 7. Also set `run_untagged=false` on runner 7 in the interim.
3. **Either way**: deploys move to pull-by-digest (Buildx `--metadata-file` → `containerimage.digest` artifact); add `resource_group` to deploy jobs; stop building on the production host.
4. **Record the single-developer tripwire** in LT-7 docs/memory.
5. **Open host checks** (admin): (i) can containers co-resident on traefik-net reach portainer:9000 directly, bypassing the auth proxy? (portainer confirmed on traefik-net @ 172.25.0.160; networkingmanager itself joins only its auth-net + postgres-net); (ii) admin builds confirmed NOT on runner 10 (still on privileged admin dind runners — deferred cleanup), so no cross-tenant build-cache issue today, but it becomes one if admin builds migrate there.

## Risks flagged

- Runner-3 SSH key exfiltration = persistent host root (lateral movement from any protected-ref dev job).
- Mutable `latest` tag = whoever can push the tag controls production content.
- Auto-deploy removes the human-in-the-loop that manual deploys had — compromised laptop/session → unattended production deploy.
- Secret exfiltration is inherent in handing an env file to a developer-built image — env files must hold only credentials the app is entitled to.
- Network attachment is a capability: deployed dev containers can probe everything on their networks; DB auth/ACLs protect admin resources, not container naming.
- Shared-kernel container isolation is the residual boundary in B2 — real but weaker than a VM; kernel exploits remain out of scope of any single-host design.
