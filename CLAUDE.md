# CLAUDE.md — AI Agent Context for pfeerick/dotfiles-bootstrap

This file provides context for AI coding assistants. Read it before making changes.
See README.md for user-facing documentation.

> **Maintenance:** If you change the bootstrap flow, add new native installs, or modify the handoff contract, update this file as part of the same commit.

## Repository Role

This is **Stage 1** of a two-stage dotfile system. Its only job is to get a machine to the point where `chezmoi init --apply` can run against the Stage 2 repo (`pfeerick/dotfiles`). Keep it minimal — broad tool/package convergence belongs in Stage 2.

## Stage 1 Scope Rules

Stage 1 **should**:
- Install minimal prerequisites (git, curl, python3)
- Install and authenticate GitHub CLI (`gh`)
- Install chezmoi
- Write the Stage 1→2 handoff contract to `~/.config/dotfiles-bootstrap/handoff.env`
- Run `chezmoi init --apply` against the Stage 2 repo

Stage 1 **should not**:
- Install broad working tools (those belong in `packages/tools.manifest.json` in Stage 2)
- Manage SSH keys (Stage 2 does this via `run_once_20_fetch_ssh_keys.sh.tmpl`)
- Apply host-specific personal configuration

## Windows Bootstrap Flow

The Windows bootstrap (`bootstrap-windows.ps1`) is more complex than Linux/macOS because it runs chezmoi in **two contexts**:

```
bootstrap-windows.ps1 (PowerShell, Admin)
  1. Install WSL2 + Ubuntu (may require reboot)
  2. Install WezTerm via winget
  3. Install chezmoi + gh natively via winget
  4. Refresh PATH (so newly installed tools are visible without reopening shell)
  5. WSL inner script (bash):
     a. Install deps: curl, git, python3, gh
     b. Install chezmoi in WSL (~/.local/bin)
     c. Interactive gh auth login
     d. Write handoff.env contract
     e. chezmoi init --apply (deploys Unix/zsh dotfiles, runs all run_onchange_* scripts)
  6. Run Stage 2 native Windows installer (install_windows_native_tools.py via WSL)
     → installs all winget packages from tools.manifest.json
  7. Authenticate gh natively by extracting token from WSL gh session (no second login)
  8. chezmoi init --apply natively (deploys Windows dotfiles: gitconfig, wezterm, PS profile, etc.)
```

Key design decisions:
- **Token reuse**: `wsl bash -lc 'gh auth token'` extracts the WSL gh token for native gh auth, avoiding a second interactive login
- **PATH refresh**: after winget installs, `[System.Environment]::GetEnvironmentVariable("PATH", ...)` reloads PATH in the current session
- **No stub wezterm config**: the old hardcoded stub was removed; chezmoi now deploys the managed `dot_wezterm.lua` directly

## Handoff Contract

The WSL script writes `~/.config/dotfiles-bootstrap/handoff.env` before running `chezmoi init --apply`. Stage 2 validates this in `run_before_00_validate_stage1_handoff.sh.tmpl`. Required fields:

```
STAGE1_PROVIDER=dotfiles-bootstrap
STAGE1_OS=windows-wsl | linux | darwin
STAGE1_GITHUB_USER=...
STAGE1_REPO_NAME=...
STAGE1_REPO_URL=...
STAGE1_GENERATED_AT=<ISO8601>
```

Contract spec: `docs/stage1-stage2-contract.md`

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `GITHUB_USER` | Yes (non-interactive) | GitHub username |
| `REPO_NAME` | No | Defaults to `dotfiles` |
| `BOOTSTRAP_NONINTERACTIVE` | No | Set to `1` to disable prompts |
| `BOOTSTRAP_CI_TEST` | No | Set to `1` for CI mode (skips WSL/Stage 2) |
| `GH_TOKEN` | CI only | Token for non-interactive gh auth |

## CI Mode

`BOOTSTRAP_CI_TEST=1` skips WSL provisioning and Stage 2 handoff entirely — it only validates that `gh` is installed and authenticated. Used in `.github/workflows/ci.yml`.
