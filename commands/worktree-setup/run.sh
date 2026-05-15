#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pack_dir="${GC_PACK_DIR:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}"

case "${1:-}" in
  -h|--help)
    sed -n '1,120p' "$script_dir/help.md"
    exit 0
    ;;
esac

exec "$pack_dir/assets/scripts/gc-beads-lite-worktree-setup.sh" "$@"
