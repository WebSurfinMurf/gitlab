# Testing — GitLab Project

## LX Extension Verification
- `verify.sh` runs 6 automated checks after apply.sh:
  1. `GitlabEdition.extensions` includes `lx`
  2. `Board#board_labels` association responds
  3. `Board#scoped?` returns false for unscoped boards
  4. `LX::BoardLabel.count` returns integer
  5. Extension files present in container (>=5 .rb files)
  6. `board_labels` table accessible via psql

## Manual Verification
- Rails console: `docker exec gitlab gitlab-rails runner 'puts Board.find(ID).scoped?'`
- Ancestor check: `Boards::Issues::ListService.ancestors.first(5)` should show `LX::` module
- Board UI: open scoped board, verify only matching-label issues appear

## Upgrade Testing
- apply.sh verifies patch targets before applying (grep for expected lines)
- If verification fails, saves `.current` files for manual diff against `.original` references
- Test after every GitLab version upgrade
