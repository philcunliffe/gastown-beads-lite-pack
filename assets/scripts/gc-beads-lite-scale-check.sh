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

# Count two disjoint sets of work the target should be doing:
#   1. Beads assigned directly to the target (e.g. refinery after a polecat
#      handoff sets assignee=<refinery-target>). These need a session even
#      though they are not unassigned.
#   2. Routed unassigned ready beads (the classic pool case for polecats).
#
# The sets are disjoint by construction: assigned beads fail --unassigned,
# unassigned beads fail --assignee=$target.
assigned_json="$("$bd_cli" list --status open,in_progress --assignee="$target" --exclude-type=epic --json --limit=0)"
routed_json="$("$bd_cli" ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json --limit=0)"

assigned=$(printf '%s\n' "$assigned_json" | jq 'length')
routed=$(printf '%s\n' "$routed_json" | jq 'length')
printf '%d\n' "$((assigned + routed))"
