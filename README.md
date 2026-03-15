# dotfiles-bootstrap

Public Stage 1 bootstrap for a private chezmoi dotfiles repository.

This repository is intentionally minimal. It installs only what is needed to authenticate and hand off to Stage 2 (`chezmoi init --apply`).

## Quick Start

Linux:

```bash
GITHUB_USER=pfeerick REPO_NAME=dotfiles curl -fsSL https://raw.githubusercontent.com/pfeerick/dotfiles-bootstrap/master/bootstrap-linux.sh | bash
```

macOS:

```bash
GITHUB_USER=pfeerick REPO_NAME=dotfiles curl -fsSL https://raw.githubusercontent.com/pfeerick/dotfiles-bootstrap/master/bootstrap-macos.sh | bash
```

Windows (PowerShell as Administrator):

```powershell
$env:GITHUB_USER="pfeerick"; $env:REPO_NAME="dotfiles"; irm https://raw.githubusercontent.com/pfeerick/dotfiles-bootstrap/master/bootstrap-windows.ps1 | iex
```

## Environment Variables

- `GITHUB_USER` (required in non-interactive mode)
- `REPO_NAME` (optional, defaults to `dotfiles`)
- `BOOTSTRAP_NONINTERACTIVE` (optional; set to `1` to disable prompts)
- `BOOTSTRAP_CI_TEST` (optional; set to `1` to run CI test mode and skip Stage 2 handoff)
- `GH_TOKEN` (required when `BOOTSTRAP_CI_TEST=1` and `gh` is not already authenticated)
- `BOOTSTRAP_VERBOSE` (optional; set to `1` for more logging)

## Scope

Stage 1 should:

- Install minimal prerequisites for bootstrap
- Ensure GitHub authentication is available
- Install/locate chezmoi
- Run `chezmoi init --apply` against Stage 2

Stage 1 should not:

- Manage personal SSH key fetching
- Do broad package/tool convergence
- Apply host-specific personal configuration beyond bootstrap requirements

## Repository Structure

- `bootstrap-linux.sh`: Linux entrypoint
- `bootstrap-macos.sh`: macOS entrypoint
- `bootstrap-windows.ps1`: Windows entrypoint (WSL-first handoff)
- `lib/`: shared shell helpers (gradual refactor target)
- `scripts/`: local lint/smoke test utilities
- `.github/workflows/ci.yml`: shell lint and syntax checks

## Development

Run local checks:

```bash
./scripts/test-shellcheck.sh
./scripts/test-matrix.sh
```

## Notes

- Current commands use the `master` branch raw URL for parity while migrating from gist.
- After first stable release, switch examples to release-pinned URLs.
