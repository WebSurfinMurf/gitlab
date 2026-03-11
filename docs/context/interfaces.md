# Interfaces — GitLab Project

## LX Extension Interfaces

### LX::Board (prepended module)
- `has_many :board_labels` — LX::BoardLabel, FK board_id
- `has_many :labels, through: :board_labels`
- `def scoped?` — returns `board_labels.any?` (overrides CE's `false`)

### LX::BoardLabel (ActiveRecord model)
- Table: `board_labels` (exists in CE schema, unused without extension)
- Columns: `id`, `board_id`, `label_id`, `project_id`, `group_id`, `created_at`, `updated_at`
- `belongs_to :board`
- `belongs_to :label`

### LX::Boards::Issues::ListService
- Overrides `filter(items)` — adds label_links EXISTS subquery per board_label
- Only activates when `board.scoped? && board.board_labels.any?`

### LX::Boards::CreateService / UpdateService
- Intercept `params[:labels]` for board scope management
- Note: Grape API layer strips `labels` param before it reaches services (CE whitelist limitation)
- Scoping currently done via `scope-board.sh` (direct SQL/rails runner)

## CLI Tools

### apply.sh
- Input: none (reads from extensions/ dir)
- Actions: verify patch targets, apply 3 patches, copy lx/ dir, restart rails
- Idempotent: skips already-applied patches
- Saves `.last_applied_version` for tracking

### verify.sh
- 6 checks: extensions array, board_labels assoc, scoped?, LX::BoardLabel model, file count, table access
- Exit 1 on any failure

### scope-board.sh
- Input: `<project_path> <board_name> [label_name]`
- Default label: `enhancement::{board_name}`
- Inserts into board_labels via gitlab-psql

### migrate-legacy-boards.sh
- Renames "cicd" boards to "initial", adds enhancement::initial label to unlabeled issues
