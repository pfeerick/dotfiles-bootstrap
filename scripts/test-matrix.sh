#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running basic syntax checks..."

bash -n "$repo_root/bootstrap-linux.sh"
bash -n "$repo_root/bootstrap-macos.sh"

echo "Skipping bootstrap-windows.ps1 syntax validation (requires PowerShell runtime)."

echo "matrix-smoke: OK"
