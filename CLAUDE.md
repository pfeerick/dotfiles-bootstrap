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
  5. Authenticate gh natively (interactive `gh auth login` if needed); its token is forwarded to WSL below
  6. WSL inner script (bash), with the Windows token handed over as `GH_TOKEN` via `WSLENV` for this stage only:
     a. Install deps: curl, git, python3, gh
     b. Install chezmoi in WSL (~/.local/bin)
     c. Save the forwarded token as WSL's own gh login (`gh auth login --with-token`); only if none was forwarded (or storing it fails), fall back to an interactive WSL-local `gh auth login`
     d. Write handoff.env contract
     e. chezmoi init --apply (deploys Unix/zsh dotfiles, runs all run_onchange_* scripts)
  7. chezmoi init --apply natively (deploys Windows dotfiles: gitconfig, wezterm, PS profile, etc., and installs the winget packages from tools.manifest.json)
```

Key design decisions:
- **WSL and Windows are independent at runtime**: WSL interop (running `.exe` files from the distro) drops out on its own, and everything that relied on it (`gh.exe` tokens, `npiperelay.exe`, `cmd.exe`/`winget.exe` driven from WSL) broke with it. So Stage 2 runs no Windows executables from WSL, and Stage 1 leaves WSL with its own stored `gh` login instead. The Windows stage authenticates gh first and hands the token to WSL through `WSLENV` (a `wsl.exe` feature, not interop; not on a command line), where it is saved with `gh auth login --with-token` — the same token, not a new OAuth login, so it does not count against GitHub's ten-tokens-per-app limit. Native chezmoi (step 7) is the only thing that touches the Windows side: it installs the winget packages and deploys the PS profile. The earlier designs either copied the token *out of* WSL into Windows, or kept the Windows keyring as the single source via `gh.exe`; both broke (drifted tokens, then interop outages).- **PATH refresh**: after winget installs, `[System.Environment]::GetEnvironmentVariable("PATH", ...)` reloads PATH in the current session
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
