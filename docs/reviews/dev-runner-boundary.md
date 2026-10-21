---
name: dev-runner-boundary
created: 2026-08-16
status: pending-review
---

# Is a capability broker (or socket proxy) an honest boundary for developer CI deploys on a single rootful Docker host — or is the settled LT-7 position still correct?

## Situation

websurfinmurf (the sole developer on this host) sent the administrator a well-researched note
(`/mnt/shared/aichat/websurfinmurf.developer-runner-restrictions.md` — readable at
`/workspace/administrator/../../mnt/shared/aichat/` is NOT mounted; the note's full substance is
reproduced below) asking for a way to make the failing `deploy` CI job for
`developers/networkingmanager` work, under the requirement:

> "I don't care if each developer can reach each other's stuff. I DO care developers cannot
> modify administrators' stuff."

The note inventories the four developer-group runners, correctly identifies that runner 7
(`gitlab-runner-docker-dev`: docker executor, `privileged=true`, host docker.sock mounted,
`network_mode=host`) is host-root-equivalent for any job it runs, and offers four options:

- **A.** Give runner 3 (shell executor in `gitlab-runner-dev`, job uid 999 `gitlab-runner`) a
  docker CLI + socket group + ACL on the developer's secrets file. (They reject this themselves —
  it recreates runner 7.)
- **B. (their preference)** A ~100-line root-owned "deploy broker" service on a unix socket,
  exposing one verb `deploy <project>` for an allow-list of projects. Runner 3 gets no docker
  capability, only the right to request a named pre-approved action.
- **C.** `tecnativa/docker-socket-proxy` filtered socket. (They rate it "better than A, weaker
  than B" — filters by API endpoint, not container name.)
- **D.** Status quo: deploy by hand, delete the CI deploy job.

They also ask for a decision on runner 7 ("retire or lock down — matters more than our deploy
job") and explicitly requested Review Board input on this narrow question:

> "Given a requirement that 'developers cannot modify administrators' resources' on a single
> shared Docker host, is a filtered socket proxy an acceptable boundary, or is a
> capability-style broker the only honest answer?"

## Prior settled decision (LT-7, 2026-06-04, Review Board-backed)

This ground was covered two months ago. The settled model
(grounded in `/workspace/administrator/projects/portainer/docs/no-rootless.md` and
`/workspace/administrator/projects/portainer/docs/reviews/kaniko-replacement-builder.final.md`):

1. On this single **rootful** Docker daemon, ANY docker-capable identity is host-root-equivalent
   (`docker run --privileged -v /:/host`). Separate deploy uids, socket proxies, docker-group
   removal, and per-network ACLs are boundaries an attacker steps over — "a ritual, not a
   boundary." The same logic killed a rootless-docker migration (host disables unprivileged
   userns as hardening).
2. Therefore docker-group-for-developers is **intentional and accepted**: websurfinmurf the
   human is in groups `docker` AND `sudo` — the requested boundary is unenforceable against
   the developer-as-human on this host, full stop. The structural fix (backlogged, accepted
   risk) is a separate host; the real live boundaries are elsewhere (IBKR-side account caps,
   no docker.sock in agent runtime containers, manual live deploys).
3. CI tier model implemented: tests → runner 9 (`dev-ci`, non-privileged, no socket);
   image builds → runner 10 (KVM build VM, tag `build`, shell executor, BuildKit,
   ref_protected — build where the capability lives, in a VM with its own kernel);
   deploys → runner 3 (shell, ref_protected).
4. Runner 7 was set `ref_protected` on 2026-06-04, closing the pre-merge/MR root-equivalent
   path. Its retirement is blocked on ONE job: `developers/ib-gateway` still builds via
   untagged `docker:25-dind` jobs, which land on runner 7 (the only developer runner with
   `run_untagged=true`).

## Verification performed today (2026-08-16, on the host)

- Runner 7: `privileged=true`, socket mounted, host network — confirmed. But `access_level:
  ref_protected` — the note's claim "anyone who can push a branch can reach it" is **stale**;
  only protected refs reach it now.
- Runner 3: no docker CLI, uid 999 in group 999 only — confirmed. **BUT**: the container ships
  `/home/gitlab-runner/.ssh/id_ed25519` and `ssh websurfinmurf@localhost` from the job user
  **works today, non-interactively**, landing as uid 1000 websurfinmurf with groups
  `docker(127)`, `sudo`, `developers`. This is the documented runner architecture in
  `/workspace/administrator/projects/gitlab/CLAUDE.md` ("Runner SSHs to localhost as the
  target user"), and it is exactly how the admin runner deploys.
- So the note's blockers #2 (uid 999 can't read the secret) and #3 (no docker client) are
  artifacts of running the deploy inline as uid 999 — the wrong pattern. Via SSH-as-websurfinmurf
  the job reads his own secrets and uses his own docker membership. Nothing needs granting.
- Consequence they missed: runner 3 jobs on protected refs ALREADY hold full websurfinmurf
  identity (= host-root-equivalent). "Runner 3 stays as contained as it is today" is nominal
  containment only.

## My draft position (please attack it)

1. **Answer to A–D: none of the four.** Use the already-documented pattern: the `deploy` job on
   runner 3 does `ssh websurfinmurf@localhost 'cd ~/projects/networkingmanager && ./deploy.sh'`.
   Gate = `ref_protected` (only maintainers can push protected refs). This adds zero new
   capability: it automates exactly what websurfinmurf already does by hand with the same
   identity. End-state refinement: move the `docker compose build` out of deploy.sh to runner 10
   (tag `build`, push to registry — the stocktrader pattern), so deploy becomes `compose pull &&
   up -d`.
2. **Option B (the broker) is a ritual, not a boundary**, because the allow-listed verb
   `deploy networkingmanager` executes developer-controlled content: deploy.sh, the compose
   file, and the Dockerfile all live in the developer's repo. A compose file can specify
   `volumes: ["/:/host"]` or `privileged: true`; the root-owned broker would faithfully execute
   it. To be a real boundary the broker must validate/pin compose content — an ever-growing
   validator that reimplements the problem. So B launders the same host-root capability through
   a root-owned service while LOOKING like a boundary — strictly worse than being honest.
3. **Option C: same verdict as LT-7 gave socket proxies** — a bar-raiser, not a boundary.
4. **The honest answer to their §3 framing**: the requested boundary ("developers cannot modify
   administrators' stuff") is not achievable on this host against a docker-group +sudo developer,
   and LT-7 explicitly accepted that with eyes open. Runner-level hardening changes who must be
   compromised, not what a compromise yields.
5. **Runner 7**: already mitigated (ref_protected). Retirement blocked on ib-gateway's untagged
   dind jobs. The unblocking move belongs to websurfinmurf: migrate ib-gateway's build to
   runner 10 (rewrite from `image: docker:25` + dind services to plain buildx — runner 10 is a
   shell executor and ignores `image:`/`services:`). Then the administrator retires runner 7.

## What I Need

1. Attack point 2 hard: is there a broker design at ~100-line scale that would actually
   constrain developer-controlled compose content, or is my "ritual" verdict correct?
2. Is the SSH-as-target-user pattern (point 1) the right recommendation, or does it have a
   failure mode I'm missing (e.g., does ref_protected + protected-branch config on the
   developer side actually gate who triggers it, given websurfinmurf is Owner of his group)?
3. Sanity-check point 4: is it correct and honest to tell the requester their stated boundary
   is unachievable-by-construction here, with the separate-host as the only structural close?
4. Anything the note or my draft both miss?

## Constraints

- Single shared rootful Docker host; unprivileged userns disabled (hardening decision, settled).
- Rootless docker: evaluated and rejected (no-rootless.md). Do not re-propose.
- projects/gitlab (runner configs) is hard-denied to autonomous sessions except docs/ —
  any runner config change is a human/administrator action.
- One developer human today (websurfinmurf); scale-out is not a current requirement.
- LT-7 decisions (docker-group-for-devs, build-VM, tier model) are settled — challenge only
  with substantive new argument, not preference.
