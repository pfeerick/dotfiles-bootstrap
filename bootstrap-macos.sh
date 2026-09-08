#!/bin/bash
# bootstrap-macos.sh
# Setup for macOS (works with private repos via gh CLI)
# Usage: curl -fsSL https://YOUR_PUBLIC_URL/bootstrap-macos.sh | bash
# Or if script is local: ./bootstrap-macos.sh

set -euo pipefail

# Bumped when a change to Stage 1's bootstrap strategy (e.g. which package
# manager is used) would be useful for Stage 2 or a future re-run to detect.
# See docs/stage1-stage2-contract.md.
STAGE1_BOOTSTRAP_VERSION="2"

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

# Homebrew's support for older Intel-only macOS releases is narrowing, while
# MacPorts still supports them well. Apple Silicon keeps using Homebrew;
# Intel Macs bootstrap through MacPorts instead. Stage 2 (dotfiles) makes the
# same split for its own broader tool manifest.
ARCH="$(uname -m)"

if [ "$ARCH" = "arm64" ]; then
    PKG_MANAGER="brew"

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

    # Install Python 3 if not present
    if ! command -v python3 &> /dev/null; then
        echo "Installing Python 3..."
        brew install python
    fi

    # Install chezmoi if not already installed
    if ! command -v chezmoi &> /dev/null; then
        echo "Installing chezmoi..."
        brew install chezmoi
    fi
else
    PKG_MANAGER="port"

    # Intel Mac: bootstrap MacPorts if not present, then install the same
    # minimal prerequisite set via `port` instead of `brew`.
    if ! command -v port &> /dev/null; then
        echo "Installing MacPorts..."

        MACOS_VERSION="$(sw_vers -productVersion)"
        MAJOR="${MACOS_VERSION%%.*}"
        MINOR="0"
        if [[ "$MACOS_VERSION" == *.* ]]; then
            REST="${MACOS_VERSION#*.}"
            MINOR="${REST%%.*}"
        fi

        CODENAME=""
        if [ "$MAJOR" -ge 11 ]; then
            case "$MAJOR" in
                11) CODENAME="11-BigSur" ;;
                12) CODENAME="12-Monterey" ;;
                13) CODENAME="13-Ventura" ;;
                14) CODENAME="14-Sonoma" ;;
                15) CODENAME="15-Sequoia" ;;
                26) CODENAME="26-Tahoe" ;;
                *) CODENAME="" ;;
            esac
        else
            case "${MAJOR}.${MINOR}" in
                10.13) CODENAME="10.13-HighSierra" ;;
                10.14) CODENAME="10.14-Mojave" ;;
                10.15) CODENAME="10.15-Catalina" ;;
                *) CODENAME="" ;;
            esac
        fi

        if [ -z "$CODENAME" ]; then
            echo "ERROR: Could not determine a matching MacPorts installer for macOS $MACOS_VERSION."
            echo "Install MacPorts manually from https://www.macports.org/install.php, then re-run this script."
            exit 1
        fi

        echo "Detected macOS $MACOS_VERSION -> $CODENAME"

        LATEST_JSON="$(curl -fsSL https://api.github.com/repos/macports/macports-base/releases/latest || true)"
        if [ -z "$LATEST_JSON" ]; then
            echo "ERROR: Failed to query the MacPorts GitHub releases API."
            echo "Install MacPorts manually from https://www.macports.org/install.php, then re-run this script."
            exit 1
        fi

        ASSET_URL="$(printf '%s' "$LATEST_JSON" | grep -o "\"browser_download_url\": *\"[^\"]*${CODENAME}\.pkg\"" | head -n1 | sed -E 's/.*"(https[^"]+)"/\1/')"

        if [ -z "$ASSET_URL" ]; then
            echo "ERROR: No MacPorts release asset found matching $CODENAME."
            echo "Install MacPorts manually from https://www.macports.org/install.php, then re-run this script."
            exit 1
        fi

        TMP_PKG="$(mktemp -t macports).pkg"
        trap 'rm -f "$TMP_PKG"' EXIT

        echo "Downloading $ASSET_URL"
        curl -fsSL -o "$TMP_PKG" "$ASSET_URL"

        echo "Installing MacPorts (requires sudo)..."
        sudo installer -pkg "$TMP_PKG" -target /
    fi

    if [ -d /opt/local/bin ]; then
        export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
    fi

    if ! command -v port &> /dev/null; then
        echo "ERROR: MacPorts installer ran but 'port' is still not on PATH."
        exit 1
    fi

    echo "Installing prerequisites via MacPorts..."
    sudo port install git gh python313 chezmoi
    sudo port select --set python3 python313
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
        echo "STAGE1_PKG_MANAGER=$PKG_MANAGER"
        echo "STAGE1_BOOTSTRAP_VERSION=$STAGE1_BOOTSTRAP_VERSION"
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
