#!/usr/bin/env bash

set -euo pipefail

detect_os() {
  local uname_out
  uname_out="$(uname -s)"
  case "$uname_out" in
    Linux) echo "linux" ;;
    Darwin) echo "macos" ;;
    *) echo "unknown" ;;
  esac
}

detect_linux_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}
