#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: gc-beads-lite-scale-check.sh <qualified-target> [scope-root]}"
scope_root="${2:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pack_dir="${GC_PACK_DIR:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}"
bd_cli="${GC_BEADS_LITE_WRAPPER:-$pack_dir/assets/bin/bd}"

if [ -n "$scope_root" ]; then
  export BEADS_DIR="$scope_root/.beads"
fi

ready_json="$("$bd_cli" ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json --limit=0)"
printf '%s\n' "$ready_json" | jq 'length'
