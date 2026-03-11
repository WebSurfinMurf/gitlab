# Requirements — GitLab Project

## Core Purpose
- Self-hosted GitLab CE with SSO, CI/CD, container registry, GitHub mirroring
- Custom extensions (LX) to bring Premium board features to CE

## LX Extension System
- [IMPLEMENTED] Board-level label scoping — boards show only issues matching scoped labels
- [IMPLEMENTED] `enhancement::` scoped labels convention for multi-board projects
- [IMPLEMENTED] `initial` as default board name for greenfield project builds
- [IMPLEMENTED] Upgrade-safe patching — verify patch targets before applying

## Board Conventions
- One board per enhancement (e.g., `initial`, `multiuser`)
- Board scoped to `enhancement::{board_name}` label
- Standard columns: backlog, ready, in-progress, review, blocked, done
- Cards use checkbox-based workflows (blockers, approval gates)

## CI/CD Runner System
- Per-user runners (administrator, websurfinmurf)
- Shell executor, SSH to localhost as target user
- Tag-based job routing
