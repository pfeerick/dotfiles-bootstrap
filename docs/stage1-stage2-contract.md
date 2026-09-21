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
- `gh auth status` succeeds, using the distro's own stored login on WSL too (the Windows bootstrap saves the Windows token there). Stage 2 runs no Windows executables from WSL, so nothing depends on `gh.exe` or WSL interop.

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
- `STAGE1_PKG_MANAGER=<brew|port|apt|dnf|unknown>` — the package manager Stage 1 used
  to install its own prerequisites (`git`/`gh`/`python3`/`chezmoi`) on this run. On
  macOS this reflects the arch-conditional choice (`brew` on Apple Silicon, `port` on
  Intel); on Linux/WSL it reflects the detected distro's manager.
- `STAGE1_BOOTSTRAP_VERSION=<integer>` — bumped whenever a change to Stage 1's
  bootstrap strategy (most notably, which package manager it uses) would be useful
  for Stage 2 or a future Stage 1 re-run to detect. Currently `2` (introduced
  alongside `STAGE1_PKG_MANAGER` when macOS gained the Homebrew/MacPorts arch split;
  `1` is retroactively "the original contract, before these two fields existed").

Neither field drives any behavior yet — they exist so a future bootstrap run can
compare the previous run's recorded manager/version against what it would choose today
(e.g. "this Intel Mac was bootstrapped with Homebrew under an older version") and
decide whether to warn, prompt, or migrate. No such logic is implemented yet.

## Backward Compatibility

- Older machines that were provisioned before this contract may not have a handoff marker.
- Machines provisioned before `STAGE1_PKG_MANAGER`/`STAGE1_BOOTSTRAP_VERSION` existed
  will have a marker missing those two keys — treat their absence as "version 1,
  manager unknown," not as an error.
- Stage 2 preflight should warn (not fail) when marker is missing, but should still validate core command availability.

## CI Test Mode

- When `BOOTSTRAP_CI_TEST=1`, Stage 1 validates auth and script behavior but intentionally skips Stage 2 handoff.
- CI mode does not need to write a persistent marker.
