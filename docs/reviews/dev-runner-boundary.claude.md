---
source: claude
reviewed: 2026-08-16
context: dev-runner-boundary.md
---

# Review: dev-runner-boundary — the "broker is a ritual" claim does not survive contact

**TL;DR:** Your verdict on option C is correct and now verified. Your verdict on option B is correct only against the weakest broker design — the one that executes developer-controlled content — and you've generalized it to designs it doesn't cover. There is a ~100-line broker shape that genuinely constrains developer compose/Dockerfile content, because it never reads them. Whether it's *worth building* depends on a threat-model distinction (human vs. CI-path) that both the note and your draft conflate, and your recommended SSH pattern and any broker are mutually exclusive — the SSH key you found in runner 3 is the load-bearing fact of this whole review, and your draft absorbed it into the recommendation instead of raising it as a finding.

## 1. Assessment of the draft position

**Point 1 (SSH-as-target-user):** Defensible *as an explicit "we choose no CI boundary" decision*, and "adds zero new capability" is literally true — but for an uncomfortable reason: the key already sits in runner 3, usable by **any** job any developer project schedules onto that runner, deploy job or not. Your argument is really "the status quo is already boundary-free, so automating within it costs nothing." True, but it entrenches the hole rather than deciding about it.

**Point 2 (broker = ritual):** Overstated. You refuted broker-executes-deploy.sh and generalized to all brokers.

**Point 3 (socket proxy):** Correct, and now verified: `tecnativa/docker-socket-proxy` filters by API *endpoint section* via env toggles and does not inspect request bodies — so it cannot block `privileged: true` or bind mounts inside a container-create call even in principle. (Actively maintained — latest release v0.5.0 — reject it for fit, not staleness.)

**Point 4 (boundary unachievable):** Half right. True: unachievable against **websurfinmurf-the-human** while he holds `docker`+`sudo` — LT-7 stands. False as a general claim: an honest boundary for the **CI path** is constructible. "Runner-level hardening changes who must be compromised, not what a compromise yields" is exactly backwards for the B2 design — its entire effect is changing what a compromise yields (host root → confined container).

**Point 5 (runner 7 "already mitigated"):** Overstated. Protected-branch configuration needs only Maintainer, and websurfinmurf is Owner of the developers group, so he can protect any branch on any of his projects and reach runner 7 at will. `ref_protected` mitigates the MR/fork path — against the group Owner it gates nothing. Combined with `run_untagged=true`, a stray untagged job on a protected ref still lands on a privileged, socket-mounted, host-network runner. Put a retirement date on it, don't call it mitigated.

## 2. The attack you asked for: is a small honest broker possible? Yes.

**B0 — broker runs the repo's `deploy.sh`.** Pure capability laundering. Your ritual verdict is fully correct here; this is what the developer's note describes. Concede nothing on B0.

**B1 — broker runs fixed verbs against the *developer's* compose file.** Still dev-controlled pod-spec (`privileged`, `cap_add`, `devices`, bind mounts, `network_mode: host`, `pid: host`, …). Your instinct is right that validating this is where brokers go to die — but a default-deny key allowlist fails *closed* (availability, not security). The real objections are canonicalization fidelity and TOCTOU. Don't build B1, but it's fragile, not impossible.

**B2 — the design that breaks your argument: the broker never reads developer YAML at all.**
- Compose file per allow-listed project is **root-owned, admin-authored** (e.g. `/etc/deploy-broker/networkingmanager.yml`), pinning networks, volumes, limits, and image as `registry…/networkingmanager@${DIGEST}`.
- Developer pipeline builds on runner 10 and pushes to the registry.
- Broker exposes one verb: `deploy <project> <sha256:digest>`, regex-validated, unix-socket peer-cred checked, logged. Substitutes digest, runs compose pull/up against the root-owned file, builds disabled.

Genuinely ~100 lines, no validator, because **pod-spec authority never leaves root's hands**. A digest is content-addressed, so the verb's argument carries no confinement authority — exactly "run your code, in my box."

**What B2 reduces:** compromised CI job drops from "full websurfinmurf identity = host root" to "arbitrary code inside an admin-pinned, default-confined container." Residual = standard shared-kernel container isolation — the same boundary separating every other container on this estate. If you call it a ritual, the whole platform is a ritual — that proves too much. LT-7's mantra is true and irrelevant: B2's point is that the CI job is *not* docker-capable; quoting the mantra against it is circular.

**Honest limits of B2:**
1. CI path only — the human walks around it. LT-7's verdict stands against him.
2. Only as strong as the weakest parallel path. With `id_ed25519` in runner 3 and runner 7 alive, B2 is theater. **Recommendation 1 and any broker are mutually exclusive.**
3. Cost is friction: every pod-spec change becomes an admin action. One developer/one project = a handful per year; at scale, a queue.

**Whom is B2 for?** A compromised developer laptop/session/token pushing to protected refs; a malicious dependency shaping build outputs; and **developer #2**, who under the SSH pattern inherits websurfinmurf's full identity the day they become Maintainer.

## 3. What I'd do differently, concretely

1. **Split the answer by threat model, explicitly.** "Can developers-as-humans be stopped?" → No (LT-7, settled). "Can the CI path be prevented from escalating past its container?" → Yes (B2, or the VM below). The requester's §3 question is the *second* question; your draft answers the first.
2. **Decide the runner-3 SSH key before choosing any option.** Either an intended capability grant (say so in writing; broker debate moot) or an accident of copying the admin runner's architecture (remove it; B2 becomes coherent). It cannot stay an unexamined default.
3. **Put a same-host KVM VM on the table for dev *workloads*, not just builds.** Deploy networkingmanager into a dedicated dev VM where developers get full docker freedom, Traefik routing to the VM IP. Kernel-level boundary, no broker, no compose-ownership friction — the estate already operates this pattern (runner 10). "Separate host as the only structural close" is false; a guest on the same iron closes the stated requirement without new hardware.
4. **End-state deploy = pull by digest, not tag**, whichever option wins.

## 4. Risks and gotchas missed by both

- **Registry tag mutability** — applies to point-1 end-state too.
- **Runner 10 cross-tenant builds.** If admin and dev builds share the build VM's daemon/cache (shell executor ⇒ persistent state), a dev build can poison admin build cache — violating the boundary in the build tier. Check whether admin builds use runner 10.
- **Network adjacency of the deployed container.** `portainer-app` sits on `traefik-net` holding the docker socket, OAuth2 enforced by a proxy *in front* — container-to-container traffic may reach Portainer's port directly, bypassing Traefik. If so, any deployed dev container is one HTTP hop (plus Portainer's native auth) from full docker control, mooting the runner debate at the network layer. Verify.
- **Auto-deploy removes the human-in-the-loop.** "Compromised laptop/key/session → production deploy" becomes fully unattended. Option D preserved that; worth one sentence of eyes-open acceptance.
- **`StrictHostKeyChecking=no`** baked into the documented CI example.
- **If B2 is built:** TOCTOU hygiene, no symlink-following into dev-controlled paths, strict digest regex, peer-cred allowlist, append-only logging.

## 5. Blind spots a same-context reviewer would miss

1. **The no-rootless pattern-match runs backwards here.** no-rootless.md killed the VM *for protecting live from an actor already holding the rootful socket*. Here you're protecting the host *from* a workload — precisely the direction VM isolation binds. The settled decision doesn't transfer.
2. **"Boundary" has been quietly redefined as "stops the human."** Under that definition nothing short of a separate host qualifies and "ritual" becomes unfalsifiable. On the CI-path definition, real boundaries exist. Name the definition before issuing the verdict.
3. **The SSH key is the finding, not the mechanism.** The draft's response to discovering it was to build the recommendation on top of it. A fresh reviewer's first reaction is "that's the headline."
4. **Every conclusion is load-bearing on "exactly one, trusted developer" — write down the tripwire.** The day a second developer gets Maintainer on any developers project, the SSH pattern hands them websurfinmurf's host-root-equivalent identity and this decision reopens.
5. **The note's option B came from the person it would constrain.** Whoever owns the boundary must author it.

## Verdict

Filtered socket proxy: **not** an acceptable boundary (cannot see request bodies). A capability broker **can** be honest at ~100-line scale, but only the digest-only variant (admin-owned compose), and only with parallel paths closed (runner-3 SSH key removed for dev jobs, runner 7 retired). The "ritual" verdict is correct for B-as-written, wrong as a generalization. Point 4 splits into "unachievable against the human (settled)" and "achievable against the CI path (a choice)." Strongest structural close short of new hardware: a dev-workloads KVM guest. Before deciding, check Portainer-on-traefik-net adjacency — it may moot the runner debate from the network side.

**Open (host-side checks only the administrator can run):** does anything on traefik-net reach portainer-app directly; do admin builds share runner 10's daemon with dev builds; is the runner-3 SSH key intended or inherited.
