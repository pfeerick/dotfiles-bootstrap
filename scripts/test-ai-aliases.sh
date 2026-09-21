#!/usr/bin/env bash
# Every other AI tool's instruction file must be a git symlink to CLAUDE.md, the one real file.
# Reads the git index, so it does not depend on the checkout having created real symlinks.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

declare -A expected=(
  [AGENTS.md]="CLAUDE.md"
  [GEMINI.md]="CLAUDE.md"
  [.cursorrules]="CLAUDE.md"
  [.windsurfrules]="CLAUDE.md"
  [.github/copilot-instructions.md]="../CLAUDE.md"
)

failed=0

claude_mode="$(git ls-files -s -- CLAUDE.md | cut -d' ' -f1)"
if [ "$claude_mode" != "100644" ] && [ "$claude_mode" != "100755" ]; then
  echo "CLAUDE.md must be a regular file (git mode $claude_mode)"
  failed=1
fi

for alias in "${!expected[@]}"; do
  entry="$(git ls-files -s -- "$alias")"
  if [ -z "$entry" ]; then
    echo "$alias is not tracked"
    failed=1
    continue
  fi
  mode="${entry%% *}"
  blob="$(echo "$entry" | cut -d' ' -f2)"
  if [ "$mode" != "120000" ]; then
    echo "$alias must be a symlink (git mode 120000), not a copy that can drift"
    failed=1
    continue
  fi
  target="$(git cat-file blob "$blob")"
  if [ "$target" != "${expected[$alias]}" ]; then
    echo "$alias points at '$target', expected '${expected[$alias]}'"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "ai instruction aliases: OK"