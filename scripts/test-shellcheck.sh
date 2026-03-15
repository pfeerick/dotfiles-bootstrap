#!/usr/bin/env bash

set -euo pipefail

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed."
  echo "Install with: brew install shellcheck  OR  sudo apt install shellcheck"
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Run shellcheck on top-level bootstrap scripts and helper libs.
find "$repo_root" -maxdepth 2 -type f \( -name '*.sh' -o -name '*.bash' \) \
  ! -path '*/.git/*' \
  -print0 | xargs -0 shellcheck

echo "shellcheck: OK"
