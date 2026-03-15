#!/usr/bin/env bash

set -euo pipefail

build_repo_url() {
  local github_user="$1"
  local repo_name="$2"
  printf 'https://github.com/%s/%s.git\n' "$github_user" "$repo_name"
}

gh_is_authenticated() {
  gh auth status >/dev/null 2>&1
}

require_gh_auth() {
  if ! gh_is_authenticated; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    return 1
  fi
}
