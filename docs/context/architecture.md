# Architecture — GitLab Project

## Components

### GitLab CE Container
- Container: `gitlab`
- Image: `gitlab/gitlab-ce:latest`
- Rails root: `/opt/gitlab/embedded/service/gitlab-rails`
- Networks: gitlab-net, traefik-net, keycloak-net
- Data: `/home/administrator/data/gitlab/`

### LX Extension System
- Uses GitLab's own `prepend_mod_with` mechanism (same as EE/JH)
- Extension dir: `lx/` under Rails root (mirrors `ee/`, `jh/` pattern)
- Source of truth: `custom-extensions/extensions/lx/` in this repo
- 3 patch points in GitLab core (applied at runtime via apply.sh)
- Extensions auto-wire via `prepend_mod_with` calls already in CE code

### Extension Module Map
```
lx/
  app/models/lx/
    board.rb            → prepended to Board (board_labels assoc, scoped?)
    board_label.rb      → standalone model (wraps existing board_labels table)
  app/services/lx/boards/
    issues/list_service.rb → prepended to Boards::Issues::ListService (filter)
    create_service.rb      → prepended to Boards::CreateService (labels param)
    update_service.rb      → prepended to Boards::UpdateService (labels param)
```

### Patch Points (3 files modified in container)
1. `lib/gitlab_edition.rb` — `%w[]` → `%w[lx]` (register extension)
2. `config/application.rb` — add `load_paths.call(dir: 'lx')` (autoload)
3. `config/initializers_before_autoloader/000_inflections.rb` — add `inflect.acronym 'LX'` (directory→constant mapping)

### Data Flow: Board Scoping
```
User opens board → Boards::Issues::ListService#execute
  → LX filter checks board.scoped? (board_labels.any?)
  → If scoped, adds WHERE clause for each board_label's label_id
  → Only issues with matching labels appear on board
```

### CI/CD Runners
- `gitlab-runner-admin` — administrator group scope
- `gitlab-runner-dev` — developer project scope (ready, not yet deployed)
- Host network, shell executor, SSH-based deployment
