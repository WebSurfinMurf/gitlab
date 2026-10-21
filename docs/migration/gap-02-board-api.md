# Executive Report — Gap 02: GitLab Scoped-Board Automation

**Status:** Open — awaiting approval
**Owner:** administrator
**Tracking card:** administrators/cicd → "[Gap] GitLab scoped-board automation broken from MCP"
**Date raised:** 2026-06-07

---

## Executive summary

The `create_gitlab_board` automation (exposed via the code-executor MCP) **fails when called from the MCP/agent context.** It tries to run `docker exec gitlab gitlab-psql …` but the MCP host has no `docker` binary, so it errors with `/bin/sh: docker: not found`. Net effect: agents can create *issues* programmatically (works fine — 15 migration cards were created this way) but cannot create *scoped boards*.

This is a **convenience/tooling gap, not a data risk.** The migration cards are fully usable today via label filtering on the project's default board.

**Recommendation:** Option B (make the tool host-independent) is the architecturally correct fix; Option A (one-off SQL from a docker-capable shell) unblocks immediately. Pursue B; use A only if a scoped board is needed before B lands.

---

## The gap — root cause

Two stacked causes:

1. **GitLab CE limitation.** Multiple issue boards per project is an EE/Premium feature; CE allows **one board per project** via API/UI. The tool works around this by writing board rows **directly into the GitLab Postgres DB**.
2. **Execution-context mismatch.** That SQL workaround is implemented as `docker exec gitlab gitlab-psql …`, which assumes the caller runs on the Docker host. The MCP runs in a container without the Docker socket/CLI, so the command isn't found.

## Why it matters (and why it's low severity)

- **Impact:** No programmatic scoped boards from automation. Manual board creation in the UI still works; label-filtered views on the default board still work.
- **Severity:** Low — purely a presentation convenience. No data loss, no blocked migration. The 15 cards are tracked correctly under `enhancement::github-migration`.

## Proposed solutions

### Option A — One-off SQL from a docker-capable shell (immediate, manual)
Run the existing board SQL directly on the host (`docker exec gitlab gitlab-psql …`) when a scoped board is actually wanted. Zero code change. Downside: manual, not reusable from automation.

### Option B — Make the MCP tool host-independent (recommended, correct end-state)
Remove the hard dependency on a local `docker` binary. Options in order of preference:
1. **GitLab API for everything possible.** Create/rename the single allowed CE board via the Boards API; only fall back to DB for the multi-board case.
2. **Reach Postgres without `docker exec`.** Connect to the GitLab DB over the network (psql to the gitlab-postgres service on its Docker network) using a read/write service credential, instead of shelling into the container.
3. **If DB-in-container is unavoidable,** give the MCP a thin, audited SSH/exec path to the host rather than assuming a local docker CLI.

### Option C — Accept default board + label filtering (no fix)
Document that scoped boards are created manually in the UI; automation only creates labeled issues. Lowest effort; abandons the automation feature.

## Recommendation

- Adopt **Option B.1 + B.2** as the real fix (API-first, network-Postgres fallback).
- Keep **Option A** documented as the manual stopgap.
- Reject **Option C** unless scoped boards turn out to be unwanted.

### Open decisions for you
- Is programmatic scoped-board creation worth the tool fix, or is label-filtering enough (→ Option C)?
- If B: acceptable to grant the MCP a network DB credential to GitLab's Postgres?

---

## Approval

- [ ] Approved — Option B (fix the tool)
- [ ] Approved — Option A only (manual stopgap, no code change)
- [ ] Approved — Option C (document & drop the feature)
- [ ] Rejected / defer

**Notes:**
