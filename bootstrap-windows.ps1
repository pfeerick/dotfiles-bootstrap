# bootstrap-windows.ps1
# Setup for Windows with WSL2 (works with private repos via gh CLI)
# Run in PowerShell as Admin:
# irm https://YOUR_PUBLIC_URL/bootstrap-windows.ps1 | iex
# Or if script is local: .\bootstrap-windows.ps1

$ErrorActionPreference = "Stop"

$isCiTest = ($env:BOOTSTRAP_CI_TEST -eq "1")
$isNonInteractive = ($env:BOOTSTRAP_NONINTERACTIVE -eq "1")
if ($isCiTest) {
    $isNonInteractive = $true
}

Write-Host "===============================" -ForegroundColor Cyan
Write-Host "Starting Windows Bootstrap..." -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""

# Get GitHub info from environment or prompt
$githubUser = $env:GITHUB_USER
$repoName = if ($env:REPO_NAME) { $env:REPO_NAME } else { "dotfiles" }

if (-not $githubUser) {
    if ($isNonInteractive) {
        Write-Host "ERROR: GITHUB_USER must be set when BOOTSTRAP_NONINTERACTIVE=1" -ForegroundColor Red
        exit 1
    }
    Write-Host "Set GITHUB_USER environment variable or pass as parameter:" -ForegroundColor Yellow
    Write-Host '  $env:GITHUB_USER="yourname"; $env:REPO_NAME="dotfiles"; .\bootstrap-windows.ps1' -ForegroundColor Yellow
    Write-Host ""
    $githubUser = Read-Host "Enter your GitHub username"
    $repoName = Read-Host "Enter your dotfiles repo name [dotfiles]"
    if ([string]::IsNullOrWhiteSpace($repoName)) {
        $repoName = "dotfiles"
    }
}

Write-Host ""
Write-Host "Using: https://github.com/$githubUser/$repoName" -ForegroundColor Cyan
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $isCiTest) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

if ($isCiTest) {
    Write-Host "[CI-TEST] Running Windows bootstrap CI mode" -ForegroundColor Yellow

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: gh CLI not found on runner" -ForegroundColor Red
        exit 1
    }

    if (-not (gh auth status *> $null)) {
        if (-not $env:GH_TOKEN) {
            Write-Host "ERROR: GH_TOKEN must be set when BOOTSTRAP_CI_TEST=1" -ForegroundColor Red
            exit 1
        }
        $env:GH_TOKEN | gh auth login --with-token
    }

    gh auth setup-git
    Write-Host "[CI-TEST] Skipping WSL provisioning and Stage 2 handoff" -ForegroundColor Yellow
    exit 0
}

# Install WSL2 if not already installed
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Host "Installing WSL2..." -ForegroundColor Yellow
    wsl --install
    Write-Host ""
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host "WSL2 installation complete!" -ForegroundColor Yellow
    Write-Host "Please restart your computer and run this script again." -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    exit 0
}

# Check if WSL2 is actually set up
$wslStatus = wsl --status 2>&1
if ($wslStatus -match "no installed distributions") {
    Write-Host "Installing default Ubuntu distribution..." -ForegroundColor Yellow
    wsl --install -d Ubuntu
    Write-Host ""
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host "Ubuntu installed in WSL2!" -ForegroundColor Yellow
    Write-Host "Please complete the Ubuntu setup (username/password)" -ForegroundColor Yellow
    Write-Host "Then run this script again." -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    exit 0
}

# Install WezTerm if not installed
if (-not (Get-Command wezterm -ErrorAction SilentlyContinue)) {
    Write-Host "Installing WezTerm..." -ForegroundColor Yellow

    # Check for winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id wez.wezterm -e --silent --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "Please install WezTerm manually from https://wezfurlong.org/wezterm/" -ForegroundColor Yellow
        Start-Process "https://wezfurlong.org/wezterm/"
        exit 1
    }
}


# Install native tools needed for dotfile management before WSL setup
foreach ($pkg in @(
    @{ Name = "chezmoi"; Id = "twpayne.chezmoi" },
    @{ Name = "gh";      Id = "GitHub.cli"      }
)) {
    if (-not (Get-Command $pkg.Name -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $($pkg.Name) (native Windows)..." -ForegroundColor Yellow
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id $pkg.Id -e --silent --accept-source-agreements --accept-package-agreements
        } else {
            Write-Host "winget not available; skipping $($pkg.Name) install." -ForegroundColor DarkYellow
        }
    }
}

# Refresh PATH so newly installed tools are visible in this session
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH", "User")

# Authenticate gh natively FIRST, so the WSL stage below does not need a second
# interactive login: the token is handed to WSL through WSLENV (a wsl.exe feature, not
# WSL interop) and saved there as the distro's own gh login. That is the same token,
# not a new OAuth login, so it does not count against GitHub's ten-tokens-per-app limit.
# After bootstrap, WSL and Windows each use their own stored login and depend on
# nothing from each other at runtime.
Write-Host ""
Write-Host "Setting up GitHub CLI for native Windows..." -ForegroundColor Yellow
$ghToken = $null
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: gh not found on the Windows PATH (install: winget install GitHub.cli)." -ForegroundColor Yellow
    Write-Host "         WSL will fall back to its own gh login, and native dotfile deployment will be skipped." -ForegroundColor Yellow
} else {
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        gh auth login
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: gh auth login did not complete; continuing without native gh auth." -ForegroundColor Yellow
        }
    }
    gh auth status *> $null
    if ($LASTEXITCODE -eq 0) {
        gh auth setup-git
        $ghToken = (gh auth token 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { $ghToken = $null }
    }
}
$ghAuthedNative = [bool]$ghToken

Write-Host ""
Write-Host "Now setting up dotfiles inside WSL2..." -ForegroundColor Yellow
Write-Host ""

# Pass selected repo/user values through to WSL script execution.
$env:GITHUB_USER = $githubUser
$env:REPO_NAME = $repoName

# Create a script to run inside WSL2
$wslScript = @'
#!/bin/bash
set -e

# Bumped when a change to Stage 1's bootstrap strategy (e.g. which package
# manager is used) would be useful for Stage 2 or a future re-run to detect.
# See docs/stage1-stage2-contract.md.
STAGE1_BOOTSTRAP_VERSION="2"
PKG_MANAGER="apt"

echo 'Installing dependencies in WSL2...'

# Install dependencies
sudo apt update
sudo apt install -y curl git python3

if ! command -v python3 &> /dev/null; then
    echo 'ERROR: python3 is required but was not found after dependency installation.'
    exit 1
fi

# Install GitHub CLI
if ! command -v gh &> /dev/null; then
    echo 'Installing GitHub CLI...'
    type -p curl >/dev/null || sudo apt install curl -y
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install -y gh
fi

# Install chezmoi
if ! command -v chezmoi &> /dev/null; then
    echo 'Installing chezmoi...'
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
fi

# Authenticate with GitHub
echo ''
echo 'Authenticating with GitHub...'
# WSL keeps its own gh login: the dotfiles run gh from WSL without depending on Windows
# at all (WSL interop, i.e. running .exe files from the distro, drops out on its own and
# everything that relied on it broke). If the Windows side forwarded its token through
# WSLENV (as GH_TOKEN, no interop involved), save it as this distro's login instead of
# asking for a second interactive login. env -u: gh refuses to log in while GH_TOKEN or
# GITHUB_TOKEN is set, and a status check with them set would pass without any stored login.
if ! env -u GH_TOKEN -u GITHUB_TOKEN gh auth status &> /dev/null; then
    if [ -n "${GH_TOKEN:-}" ]; then
        echo 'Saving the forwarded Windows GitHub token as this distro gh login...'
        printf '%s\n' "$GH_TOKEN" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --with-token \
            || echo 'WARNING: could not store the forwarded token; falling back to an interactive login.'
    fi
fi
if ! env -u GH_TOKEN -u GITHUB_TOKEN gh auth status &> /dev/null; then
    echo 'Logging in to GitHub inside WSL...'
    env -u GH_TOKEN -u GITHUB_TOKEN gh auth login
fi
gh auth setup-git || echo 'WARNING: gh auth setup-git failed; git may prompt for credentials.'

# Initialize chezmoi
echo ''
echo "Initializing chezmoi with https://github.com/$GITHUB_USER/$REPO_NAME"
echo ''

# Ensure chezmoi is in PATH
if [ -f "$HOME/.local/bin/chezmoi" ]; then
    CHEZMOI="$HOME/.local/bin/chezmoi"
elif command -v chezmoi &> /dev/null; then
    CHEZMOI="chezmoi"
else
    echo "ERROR: chezmoi not found!"
    exit 1
fi

REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
CONTRACT_DIR="$HOME/.config/dotfiles-bootstrap"
CONTRACT_FILE="$CONTRACT_DIR/handoff.env"
mkdir -p "$CONTRACT_DIR"
{
    echo "STAGE1_PROVIDER=dotfiles-bootstrap"
    echo "STAGE1_OS=windows-wsl"
    echo "STAGE1_GITHUB_USER=$GITHUB_USER"
    echo "STAGE1_REPO_NAME=$REPO_NAME"
    echo "STAGE1_REPO_URL=$REPO_URL"
    echo "STAGE1_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "STAGE1_PKG_MANAGER=$PKG_MANAGER"
    echo "STAGE1_BOOTSTRAP_VERSION=$STAGE1_BOOTSTRAP_VERSION"
} > "$CONTRACT_FILE"

"$CHEZMOI" init --apply "$REPO_URL"

echo ''
echo '==============================='
echo 'Bootstrap complete!'
echo '==============================='
echo ''
'@

# Save the script to a temp file in WSL and execute it (so stdin stays
# connected to the terminal — required for sudo password prompts and
# interactive gh auth login).
# GetRandomFileName() produces only alphanumeric chars + one dot (removed here),
# so the resulting path contains no shell metacharacters.
$tmpScript = "/tmp/dotfiles_bootstrap_$([System.IO.Path]::GetRandomFileName().Replace('.', '')).sh"
$wslScript | wsl bash -c "cat > '$tmpScript' && chmod +x '$tmpScript'"
$prevGhToken = $env:GH_TOKEN
$prevWslEnv = $env:WSLENV
try {
    if ($ghToken) {
        # Hand the Windows token to WSL through WSLENV so it never appears on a command line
        $env:GH_TOKEN = $ghToken
        $env:WSLENV = if ($prevWslEnv) { "GH_TOKEN:$prevWslEnv" } else { "GH_TOKEN" }
    }
    wsl bash -c "GITHUB_USER='$githubUser' REPO_NAME='$repoName' bash '$tmpScript'"
} finally {
    $env:GH_TOKEN = $prevGhToken
    $env:WSLENV = $prevWslEnv
    wsl bash -c "rm -f '$tmpScript'"
}

# Deploy Windows dotfiles natively (gh was authenticated up front). This is the only thing
# that touches the Windows side: native chezmoi installs the winget packages and deploys
# the PowerShell profile itself, so nothing needs to be driven from WSL.
if ($ghAuthedNative) {
    Write-Host ""
    Write-Host "Running native chezmoi init --apply..." -ForegroundColor Yellow
    $repoUrl = "https://github.com/$githubUser/$repoName.git"
    if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
        chezmoi init --apply $repoUrl
        Write-Host "Native dotfiles deployed." -ForegroundColor Green
    } else {
        Write-Host "chezmoi not found in PATH; skipping native dotfile deployment." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "Skipping native dotfile deployment: gh is missing or not authenticated on Windows." -ForegroundColor DarkYellow
    Write-Host "Fix: winget install GitHub.cli; gh auth login; then re-run this script." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Green
Write-Host "Windows Bootstrap Complete!" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Close this PowerShell window" -ForegroundColor White
Write-Host "2. Open WezTerm (it will default to PowerShell)" -ForegroundColor White
Write-Host "3. Enjoy your consistent development environment!" -ForegroundColor White
Write-Host ""

