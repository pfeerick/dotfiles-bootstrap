#!/bin/bash
# bootstrap-macos.sh
# Setup for macOS (works with private repos via gh CLI)
# Usage: curl -fsSL https://YOUR_PUBLIC_URL/bootstrap-macos.sh | bash
# Or if script is local: ./bootstrap-macos.sh

set -euo pipefail

CI_TEST="${BOOTSTRAP_CI_TEST:-0}"
NONINTERACTIVE="${BOOTSTRAP_NONINTERACTIVE:-0}"
if [ "$CI_TEST" = "1" ]; then
    NONINTERACTIVE="1"
fi

echo "================================"
echo "Starting macOS Bootstrap..."
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
    echo "  OR: ./bootstrap-macos.sh yourname [dotfiles]"
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

# Check for sudo access on macOS
echo "Checking sudo access..."
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo access. Please enter your password."
    sudo -v
    # Keep sudo alive in background
    while true; do sudo -n true; sleep 60; kill -0 "$" || exit; done 2>/dev/null &
fi

# Install Homebrew if not present
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi

# Install GitHub CLI if not present
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    brew install gh
fi

# Install chezmoi if not already installed
if ! command -v chezmoi &> /dev/null; then
    echo "Installing chezmoi..."
    brew install chezmoi
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

# Clone and apply using gh for authentication
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
if [ "$CI_TEST" = "1" ]; then
    echo "[CI-TEST] Skipping Stage 2 handoff: chezmoi init --apply $REPO_URL"
else
    CONTRACT_DIR="$HOME/.config/dotfiles-bootstrap"
    CONTRACT_FILE="$CONTRACT_DIR/handoff.env"
    mkdir -p "$CONTRACT_DIR"
    {
        echo "STAGE1_PROVIDER=dotfiles-bootstrap"
        echo "STAGE1_OS=macos"
        echo "STAGE1_GITHUB_USER=$GITHUB_USER"
        echo "STAGE1_REPO_NAME=$REPO_NAME"
        echo "STAGE1_REPO_URL=$REPO_URL"
        echo "STAGE1_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$CONTRACT_FILE"

    chezmoi init --apply "$REPO_URL"
fi

echo ""
echo "================================"
echo "Bootstrap complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Restart your terminal (or open a new tab) for zsh to become active"
echo "2. Open WezTerm to enjoy your new setup!"
echo ""
