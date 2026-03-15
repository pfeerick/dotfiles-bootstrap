#!/usr/bin/env bash

set -euo pipefail

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_RED='\033[0;31m'
  C_YELLOW='\033[0;33m'
  C_GREEN='\033[0;32m'
  C_BLUE='\033[0;34m'
else
  C_RESET=''
  C_RED=''
  C_YELLOW=''
  C_GREEN=''
  C_BLUE=''
fi

log_info() {
  printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$*"
}

log_warn() {
  printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

log_error() {
  printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

is_noninteractive() {
  [[ "${BOOTSTRAP_NONINTERACTIVE:-0}" == "1" ]]
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

require_env_noninteractive() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  if is_noninteractive && [[ -z "$var_value" ]]; then
    die "$var_name must be set when BOOTSTRAP_NONINTERACTIVE=1"
  fi
}
