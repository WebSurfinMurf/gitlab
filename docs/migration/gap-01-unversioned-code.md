# Executive Report — Gap 01: Unversioned Custom Code

**Status:** Open — awaiting approval
**Owner:** administrator
**Tracking card:** administrators/cicd → "[Gap] Unversioned custom code — data-loss exposure"
**Date raised:** 2026-06-07

---

## Executive summary

Nine directories under `~/projects/` contain your own work but have **no version control at all** (or, in one case, a git repo with no remote). Four of them are genuine source-code applications. A single accidental `rm -rf`, disk failure, or bad edit destroys them with no recovery path — this is a **larger exposure than the GitHub-vs-GitLab question**, which at least has a remote copy on both ends.

**Recommendation:** Run a short "version the orphans" track — `git init` + secret/artifact audit + GitLab project + push — prioritising the four real apps first. Estimated effort: ~0.5 day for the four apps, ~1 day total including the large/sensitive dirs.

---

## The gap — inventory

| Dir | What it is | Size | State | Risk |
|---|---|---|---|---|
| `livekit-agent` | LiveKit voice agent (`agent.py`, Dockerfile, tests) | 144 MB | no git | **High** — own code |
| `tradingview` | TradingView data service (alert-engine + api + collector + migrations) | 528 KB | no git | **High** — own code |
| `optionsearch` | Options strategy search (api + web) | 528 KB | no git | **High** — own code |
| `tts-wrapper` | TTS wrapper service (`tts_wrapper.py`, Dockerfile) | 36 KB | no git | **High** — own code |
| `claude-code-viewer` | Session viewer with deploy + tests | 684 KB | no git | Medium |
| `ddns-updater` | Cloudflare DDNS service (has deploy.sh) | 36 KB | no git | Medium |
| `agents` | AI agent CLI infra (active 2026-06-04) | 208 MB | no git | Medium — secrets/size care |
| `backstage` | Backstage command center | 1.5 GB | no git | Medium — gitignore audit needed |
| `cups` | Print/scan server config | 11 MB | **git, no remote** | Low — just needs a remote |

## Why it matters

- **No recovery point.** No branch, no remote, no history. Loss is total and silent.
- **No CI/CD or review.** These deploy to production with no pipeline, no validation, no audit trail.
- **Inconsistent with platform intent.** Every other custom project is at least on GitHub; these aren't anywhere.

## Proposed solution

Per-directory runbook (same shape as the main migration, minus the GitHub-origin step):

1. **Audit first** — scan for secrets (`*.env`, tokens, keys) and large build artifacts; write a proper `.gitignore` before the first commit. Critical for `backstage` (1.5 GB), `agents` (208 MB), `livekit-agent` (144 MB).
2. `git init` + initial commit (cups: skip, already a repo).
3. Create GitLab project in the correct namespace (`administrators/` or `developers/`).
4. Add `gitlab` remote → push.
5. Add `.gitlab-ci.yml` where a `deploy.sh` exists (livekit-agent, tts-wrapper, ddns-updater, backstage).

### Phasing
- **Phase A — the four real apps (do first):** `livekit-agent`, `tradingview`, `optionsearch`, `tts-wrapper`.
- **Phase B — supporting tools:** `claude-code-viewer`, `ddns-updater`, `cups` (remote only).
- **Phase C — large/sensitive (needs gitignore + secret audit):** `agents`, `backstage`.

### Open decisions for you
- Namespace per dir (`administrators/` vs `developers/` — trading-related ones?).
- `backstage` 1.5 GB: confirm what's build output vs source before first commit (don't commit the 1.5 GB).
- `agents`: contains secrets? May need `secrets/` exclusion or a separate private project.

---

## Approval

- [ ] Approved — open the Phase A/B/C cards and proceed
- [ ] Approved with changes (note below)
- [ ] Rejected / defer

**Notes:**
