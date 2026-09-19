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

## macOS Bootstrap Flow

`bootstrap-macos.sh` branches on `uname -m` to pick a package manager, mirroring the
same architecture split Stage 2 makes for its own broader tool manifest:

- **Apple Silicon (`arm64`)**: installs Homebrew if missing, then `gh`/`python`/`chezmoi`
  via `brew install`. Unchanged from before the split.
- **Intel (`x86_64`)**: Homebrew's support for older Intel-only macOS releases is
  narrowing, so this path installs MacPorts instead if missing (downloading the
  versioned `.pkg` matching the detected `sw_vers -productVersion` from
  `macports/macports-base` releases, then `sudo installer -pkg ... -target /`), then
  installs `git`/`gh`/`python313`/`chezmoi` via `sudo port install` and activates the
  pinned Python via `sudo port select --set python3 python313` (MacPorts has no plain
  `python3` port). If no matching MacPorts release asset is found for the detected
  macOS version, the script exits with instructions to install MacPorts manually from
  https://www.macports.org/install.php rather than silently falling back to Homebrew.

CI exercises both paths: `macos-checks` runs on `macos-latest` (Apple Silicon, Homebrew
path); `macos-intel-checks` runs on `macos-15-intel` (a standard, non-"larger runner"
x64 image — not billed, unlike the `-large`/`-xlarge` labels) to exercise the MacPorts
bootstrap path. `BOOTSTRAP_CI_TEST=1` still skips the Stage 2 handoff and gh login, but
the package-manager bootstrap and install steps run for real on both runners.

## Windows Bootstrap Flow

The Windows bootstrap (`bootstrap-windows.ps1`) is more complex than Linux/macOS because it runs chezmoi in **two contexts**:

```
bootstrap-windows.ps1 (PowerShell, Admin)
  1. Install WSL2 + Ubuntu (may require reboot)
  2. Install WezTerm via winget
  3. Install chezmoi + gh natively via winget
  4. Refresh PATH (so newly installed tools are visible without reopening shell)
  5. Authenticate gh natively (interactive `gh auth login` if needed) — the Windows keyring is the single source of truth
  6. WSL inner script (bash), with the Windows token handed over as `GH_TOKEN` via `WSLENV` for this stage only:
     a. Install deps: curl, git, python3, gh
     b. Install chezmoi in WSL (~/.local/bin)
     c. Reuse the Windows token (`gh.exe auth token`); only if that's unavailable, fall back to an interactive WSL-local `gh auth login`
     d. Write handoff.env contract
     e. chezmoi init --apply (deploys Unix/zsh dotfiles, runs all run_onchange_* scripts)
  7. Run Stage 2 native Windows installer (install_windows_native_tools.py via WSL)
     → installs all winget packages from tools.manifest.json
  8. chezmoi init --apply natively (deploys Windows dotfiles: gitconfig, wezterm, PS profile, etc.)
```

Key design decisions:
- **Windows keyring is the source of truth for gh auth**: WSL never keeps its own long-lived token. During Stage 1 it borrows the Windows token (`GH_TOKEN` via `WSLENV`, not on a command line); afterwards Stage 2 installs a `~/.local/bin/gh` wrapper and a mise `credential_command` that fetch it on demand from `gh.exe auth token`. The earlier design copied the token *out of* WSL into Windows; two independent copies drifted and went stale (401s in gh, mise, and topgrade's WSL step). If `gh`/`gh.exe` is missing or unauthenticated, every step degrades with a clear message instead of a cryptic error.
- **PATH refresh**: after winget installs, `[System.Environment]::GetEnvironmentVariable("PATH", ...)` reloads PATH in the current session
- **No stub wezterm config**: the old hardcoded stub was removed; chezmoi now deploys the managed `dot_wezterm.lua` directly

## Handoff Contract

The WSL script writes `~/.config/dotfiles-bootstrap/handoff.env` before running `chezmoi init --apply`. Stage 2 validates this in `run_before_00_validate_stage1_handoff.sh.tmpl`. Required fields:

```
STAGE1_PROVIDER=dotfiles-bootstrap
STAGE1_OS=windows-wsl | linux | macos
STAGE1_GITHUB_USER=...
STAGE1_REPO_NAME=...
STAGE1_REPO_URL=...
STAGE1_GENERATED_AT=<ISO8601>
STAGE1_PKG_MANAGER=brew | port | apt | dnf | unknown
STAGE1_BOOTSTRAP_VERSION=<integer, currently 2>
```

`STAGE1_PKG_MANAGER`/`STAGE1_BOOTSTRAP_VERSION` are recorded but not yet acted upon —
they exist so a future bootstrap run can compare the previous run's recorded manager
against what it would choose today (e.g. an Intel Mac bootstrapped with Homebrew
before the MacPorts split existed) and decide whether to warn or migrate. No migration
logic is implemented yet. Bump `STAGE1_BOOTSTRAP_VERSION` in all three bootstrap
scripts whenever a change to this strategy would be worth detecting on a re-run.

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
