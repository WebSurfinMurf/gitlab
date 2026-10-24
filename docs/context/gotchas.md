# Gotchas — GitLab Project

## LX Extension Sharp Edges

### CUSTOM acronym breaks GitLab boot
- `inflect.acronym 'CUSTOM'` causes `IntegerOrCustomValue` → `IntegerOrCUSTOMValue`
- Ruby acronym inflections are GREEDY — affect ALL occurrences of the word
- Solution: use `LX` (short, unique, no collisions in GitLab codebase)

### prepend_mod_with must exist in target class
- Extensions only auto-wire if the target class calls `prepend_mod_with('ClassName')`
- `BaseItemsListService` does NOT have it — use `Boards::Issues::ListService` instead
- Always check: `grep -n "prepend_mod_with" path/to/service.rb`

### Grape API strips unlisted params
- CE API whitelist in `lib/api/boards.rb` does NOT include `labels` for boards
- `CreateService`/`UpdateService` label handling is dead code via HTTP API
- Board scoping must be done via `scope-board.sh` (direct DB) or `gitlab-rails runner`

### Container patches lost on upgrade
- `docker-compose down && up` recreates container, wiping patches
- Must re-run `apply.sh` after every container recreation
- board_labels DB rows persist (they're in PostgreSQL, not the container)

### docker exec grep -c returns whitespace
- `docker exec` adds whitespace to `grep -c` output
- Causes `[ "$VAR" -gt 0 ]` to fail with "integer expression expected"
- Fix: pipe through `tr -d '[:space:]'`

### docker cp creates nested dirs
- `docker cp dir/ container:/path/dir` can create `dir/dir/` nesting
- Fix: `rm -rf` target first, then copy

### path_with_namespace not a DB column
- It's a computed Rails attribute, not in the projects table
- Use: `SELECT p.id FROM projects p JOIN namespaces n ON p.namespace_id = n.id WHERE n.path || '/' || p.path = '...'`

### load_paths insertion point matters
- Must insert BEFORE "# Rake tasks ignore the eager loading settings" comment
- NOT after `load_paths.call(dir: 'jh')` — that's inside `Gitlab.jh do...end` block (only runs on JH edition)

## GitLab CE General

### Permission 502 errors
- Internal UIDs (git=998) must own files — even chmod 777 won't fix ownership checks
- Fix: `docker exec gitlab update-permissions && docker restart gitlab`

### Traefik multi-service routing
- When container has multiple Traefik services, each router MUST explicitly specify its service
- Without explicit linking: "cannot be linked automatically with multiple Services"

### Keycloak SSO hybrid URLs
- Browser endpoints: HTTPS (keycloak.ai-servicers.com:443)
- Backend endpoints: HTTP (keycloak:8080 via keycloak-net)
- `discovery: false` required in gitlab.rb

## Admin Runner CI Deploy (runner 1 / gitlab-runner-admin)

### No `jq` on the runner
- `jq: command not found` in admin jobs. `python3` IS present (validate stages use it).
- Parse JSON with `python3 -c 'import sys,json;...'`, verify with `grep`. (keycloak deploy silently skipped realm config + test:health hard-failed on this.)

### Compose project name = CI checkout dir basename
- With explicit `container_name:`, a mismatch → "container name already in use".
- Fix: pin `COMPOSE_PROJECT_NAME: <svc>` in CI `variables:`, or `cd /home/administrator/projects/<svc>` before `./deploy.sh`.

### keycloak admin API only on 8443
- Only `https://localhost:8443` is published to the host (8080 internal). Realm-config curls need `https://localhost:8443` + `-k`.

### `set -e` + `VAR=$(cmd | ...)`
- A failing command-substitution pipeline aborts the whole script. Append `|| true` for best-effort post-deploy steps.

### GitLab projects can be silently scheduled for deletion
- A project may be `marked_for_deletion_on=<date>` while still resolving via path-redirect (path shows as `<name>-deletion_scheduled-<id>`). 7 admin migration targets were found scheduled on 2026-06-07.
- Restore (cancels deletion + restores clean path): `POST /projects/:id/restore`. Root cause of the scheduling unconfirmed.
- To **reuse the path immediately** (instead of restoring) — e.g. discarding a bad import to re-create clean: hard-purge with `glab api -X DELETE "projects/:id?permanently_remove=true&full_path=<full_path>"` (202 Accepted, **async** — poll `projects/<grp>%2F<path>` until it 404s before re-creating). Done 2026-06-07 to free `administrators/mcp`.

### glab against this instance
- Set `GITLAB_HOST=gitlab.ai-servicers.com`; host `api_protocol` must be `https` (was `http` → blanket 404). cicd board = project id 18.

### API token + job-retry traps
- `GITLAB_ROOT_TOKEN` → 403 on pipeline/job retry; use `GITLAB_TOKEN_ADMIN` (both in gitlab.env).
- A `pending` job is "403 Job is not retryable" — it's picked up automatically when its runner returns; only failed/canceled jobs retry.

### Keycloak user-create 400s are password-policy rejections
- Master realm enforces `length(8)+upper+lower+digit+special`; the 400 body names the failing rule one at a time. Fetch the full policy first (`GET /admin/realms/master` → `passwordPolicy`) instead of iterating.

## Cross-Project Work From This Session

### destructive-guard blocks cross-project filesystem work
- From a `projects/gitlab`-rooted (autonomous) session, `rm`/`git init`/etc. against a SIBLING project (e.g. `projects/mcp`) are hard-blocked: "filesystem destruction outside project root". `projects/gitlab` itself is hard-deny except `docs/`.
- Material work in a sibling project → `/refocus` into it, OR hand the user a script written to `/tmp` to run (user-run `!`/scripts bypass the tool guard). Verbal authorization does NOT unblock the hook — only the path/role does.

### docker0 is a /29 — CI dies when it fills
- `default-address-pools size:29` in daemon.json also sizes the **default bridge**: 5 usable IPs. Runner 9's per-cache-volume permission containers need one each → bare-`docker run` squatters cause intermittent `no available IPv4 addresses` executor failures.
- Live fix without restart: `docker network connect <net> <c> && docker network disconnect bridge <c>` (persists across restart, not recreation). Durable fix = `bip` in daemon.json (see operations.md).

### destructive-guard also blocks host-ops writes at gitlab project root
- Writing even a non-GitLab host maintenance script to `projects/gitlab/` root is blocked (docs/ only). Host-level scripts belong in `~/scripts/`. A single Bash command mixing docs/ and non-docs paths is blocked whole — split the call.

### No `gh` CLI / GitHub token on host
- Cannot automate GitHub repo ops (visibility, mirroring) from here. Human must do via GitHub UI (set repo private: Settings → General → Danger Zone → Change visibility). The GitLab side is fully scriptable via glab.
