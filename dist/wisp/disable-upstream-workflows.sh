#!/usr/bin/env bash
# Disables every active workflow in jamesboehmer/wisp except Wisp's own
# (.github/workflows/wisp-*). Run after merging upstream. --dry-run lists
# what would be disabled.
set -euo pipefail

repo=jamesboehmer/wisp
dry_run=false
[ "${1:-}" = "--dry-run" ] && dry_run=true

gh workflow list -R "$repo" --all --json path,state \
  --jq '.[] | select(.state == "active") | select(.path | startswith(".github/workflows/wisp-") | not) | .path' |
  while read -r path; do
    if $dry_run; then
      echo "$path"
    else
      gh workflow disable -R "$repo" "$(basename "$path")"
      echo "disabled $path"
    fi
  done
