#!/bin/bash
# bootstrap-linux.sh
# Setup for Linux (works with private repos via gh CLI)
# Usage: curl -fsSL https://YOUR_PUBLIC_URL/bootstrap-linux.sh | bash
# Or if script is local: ./bootstrap-linux.sh

set -euo pipefail

CI_TEST="${BOOTSTRAP_CI_TEST:-0}"
NONINTERACTIVE="${BOOTSTRAP_NONINTERACTIVE:-0}"
if [ "$CI_TEST" = "1" ]; then
    NONINTERACTIVE="1"
fi

echo "================================"
echo "Starting Linux Bootstrap..."
echo "================================"

# Get GitHub username and repo from environment or prompt
GITHUB_USER=${GITHUB_USER:-}
REPO_NAME=${REPO_NAME:-dotfiles}

if [ -z "$GITHUB_USER" ]; then
    if [ "$NONINTERACTIVE" = "1" ]; then
        echo "ERROR: GITHUB_USER must be set when BOOTSTRAP_NONINTERACTIVE=1"
        exit 1
    fi
    echo ""
    echo "Set GITHUB_USER environment variable or pass as argument:"
    echo "  GITHUB_USER=yourname REPO_NAME=dotfiles curl ... | bash"
    echo "  OR: ./bootstrap-linux.sh yourname [dotfiles]"
    echo ""
    if [ -n "${1:-}" ]; then
        GITHUB_USER="$1"
        REPO_NAME="${2:-dotfiles}"
    else
        read -r -p "Enter your GitHub username: " GITHUB_USER </dev/tty
        read -r -p "Enter your dotfiles repo name [dotfiles]: " REPO_NAME </dev/tty
        REPO_NAME=${REPO_NAME:-dotfiles}
    fi
fi

echo ""
echo "Using: https://github.com/$GITHUB_USER/$REPO_NAME"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect Linux distribution"
    exit 1
fi

# Check for sudo
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo access. Please enter your password."
    sudo -v
fi

# Install dependencies
echo "Installing dependencies..."
case $OS in
    ubuntu|debian|linuxmint)
        sudo apt update
        sudo apt install -y curl git
        
        # Install GitHub CLI
        if ! command -v gh &> /dev/null; then
            echo "Installing GitHub CLI..."
            type -p curl >/dev/null || sudo apt install curl -y
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt update
            sudo apt install -y gh
        fi
        ;;
    fedora|centos|rhel)
        sudo dnf install -y curl git
        
        # Install GitHub CLI
        if ! command -v gh &> /dev/null; then
            echo "Installing GitHub CLI..."
            sudo dnf install -y 'dnf-command(config-manager)'
            sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            sudo dnf install -y gh
        fi
        ;;
esac

# Install chezmoi if not already installed
if ! command -v chezmoi &> /dev/null; then
    echo "Installing chezmoi..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
fi

# Authenticate with GitHub
echo ""
echo "Authenticating with GitHub..."
if ! gh auth status &> /dev/null; then
    if [ "$CI_TEST" = "1" ]; then
        if [ -z "${GH_TOKEN:-}" ]; then
            echo "ERROR: GH_TOKEN must be set when BOOTSTRAP_CI_TEST=1"
            exit 1
        fi
        printf '%s\n' "$GH_TOKEN" | gh auth login --with-token
    else
        gh auth login
    fi
fi

# Configure git to use gh as credential helper
echo "Configuring git credentials..."
gh auth setup-git

echo ""
echo "Initializing chezmoi with https://github.com/$GITHUB_USER/$REPO_NAME"
echo ""

# Ensure chezmoi is in PATH
if [ -f "$HOME/.local/bin/chezmoi" ]; then
    CHEZMOI="$HOME/.local/bin/chezmoi"
elif command -v chezmoi &> /dev/null; then
    CHEZMOI="chezmoi"
else
    echo "ERROR: chezmoi not found!"
    exit 1
fi

# Clone and apply using gh for authentication
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
if [ "$CI_TEST" = "1" ]; then
    echo "[CI-TEST] Skipping Stage 2 handoff: $CHEZMOI init --apply $REPO_URL"
else
    CONTRACT_DIR="$HOME/.config/dotfiles-bootstrap"
    CONTRACT_FILE="$CONTRACT_DIR/handoff.env"
    mkdir -p "$CONTRACT_DIR"
    {
        echo "STAGE1_PROVIDER=dotfiles-bootstrap"
        echo "STAGE1_OS=linux"
        echo "STAGE1_GITHUB_USER=$GITHUB_USER"
        echo "STAGE1_REPO_NAME=$REPO_NAME"
        echo "STAGE1_REPO_URL=$REPO_URL"
        echo "STAGE1_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$CONTRACT_FILE"

    "$CHEZMOI" init --apply "$REPO_URL"
fi

echo ""
echo "================================"
echo "Bootstrap complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Log out and log back in (or restart) for zsh to become your default shell"
echo "2. Open WezTerm to enjoy your new setup!"
echo ""
