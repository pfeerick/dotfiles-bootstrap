# Stage 1 to Stage 2 Handoff Contract

This document defines what Stage 1 guarantees before invoking Stage 2 (`chezmoi init --apply`).

## Producer

- Stage 1 bootstrap scripts in this repository.

## Consumer

- Stage 2 preflight script in the private dotfiles repository.

## Required Guarantees

1. Required commands are available:
- `git`
- `curl`
- `gh`
- `chezmoi`

2. GitHub authentication is active for the current user:
- `gh auth status` succeeds.

3. Handoff marker is written:
- Path: `$HOME/.config/dotfiles-bootstrap/handoff.env`
- Format: shell-style `KEY=VALUE` lines.

## Handoff Marker Keys

- `STAGE1_PROVIDER=dotfiles-bootstrap`
- `STAGE1_OS=<linux|macos|windows-wsl>`
- `STAGE1_GITHUB_USER=<github username>`
- `STAGE1_REPO_NAME=<repo name>`
- `STAGE1_REPO_URL=<https://github.com/user/repo.git>`
- `STAGE1_GENERATED_AT=<UTC timestamp>`

## Backward Compatibility

- Older machines that were provisioned before this contract may not have a handoff marker.
- Stage 2 preflight should warn (not fail) when marker is missing, but should still validate core command availability.

## CI Test Mode

- When `BOOTSTRAP_CI_TEST=1`, Stage 1 validates auth and script behavior but intentionally skips Stage 2 handoff.
- CI mode does not need to write a persistent marker.
