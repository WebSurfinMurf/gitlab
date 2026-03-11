# Conventions — GitLab Project

## LX Extension Naming
- Namespace: `LX` (chosen to avoid collisions — `CUSTOM` broke `IntegerOrCustomValue`)
- Directory: `lx/` under Rails root
- Ruby modules: `module LX::Boards::Issues::ListService`
- File paths mirror GitLab's own structure: `lx/app/models/lx/`, `lx/app/services/lx/boards/`

## Board Naming
- `initial` — default board for greenfield/original project builds
- Enhancement boards named after the enhancement (e.g., `multiuser`)
- Legacy boards named `cicd` should be migrated to `initial`

## Label Conventions
- `enhancement::{name}` — scoped label linking issues to enhancement boards
- Standard workflow labels: `backlog`, `ready`, `in-progress`, `review`, `blocked`, `done`
- Card type labels: `info`, `type::feature`

## Script Conventions
- All scripts in `custom-extensions/` use `set -e`
- Color-coded output: GREEN=success, YELLOW=info, RED=error
- Idempotent: check before applying, skip if already done
- Container name hardcoded as `CONTAINER="gitlab"`
