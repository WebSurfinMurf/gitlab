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
