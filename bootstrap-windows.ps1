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

# Create WezTerm config to use WSL2 by default
$weztermConfig = @"
local wezterm = require 'wezterm'

return {
  default_prog = { 'wsl.exe' },

  -- Optional: Set a nice font (install a Nerd Font for icons)
  -- font = wezterm.font 'JetBrains Mono',
  -- font_size = 11.0,
}
"@

$weztermConfigPath = "$env:USERPROFILE\.wezterm.lua"
if (-not (Test-Path $weztermConfigPath)) {
    Write-Host "Creating WezTerm config..." -ForegroundColor Yellow
    $weztermConfig | Out-File -FilePath $weztermConfigPath -Encoding UTF8
}

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
if ! gh auth status &> /dev/null; then
    gh auth login
fi

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
try {
    wsl bash -c "GITHUB_USER='$githubUser' REPO_NAME='$repoName' bash '$tmpScript'"
} finally {
    wsl bash -c "rm -f '$tmpScript'"
}

# If present, run Stage 2 native Windows installer from WSL (no env gating).
Write-Host "" 
Write-Host "Checking for Stage 2 Windows native tools installer..." -ForegroundColor Yellow
$stage2InstallerExists = (wsl bash -lc 'test -f "$HOME/.local/share/chezmoi/scripts/install_windows_native_tools.py" && echo yes || true').Trim()
if ($stage2InstallerExists -eq "yes") {
    Write-Host "Running Stage 2 Windows native tools installer..." -ForegroundColor Yellow
    wsl bash -lc 'python3 "$HOME/.local/share/chezmoi/scripts/install_windows_native_tools.py"'
} else {
    Write-Host "Stage 2 Windows native tools installer not found; skipping native Windows package install." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Green
Write-Host "Windows Bootstrap Complete!" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Close this PowerShell window" -ForegroundColor White
Write-Host "2. Open WezTerm (it will launch into WSL2 automatically)" -ForegroundColor White
Write-Host "3. Enjoy your consistent development environment!" -ForegroundColor White
Write-Host ""

