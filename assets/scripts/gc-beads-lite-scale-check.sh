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

# Count three disjoint sets of work the target should be doing:
#   1. Beads with assignee equal to the qualified target — fires for
#      singleton named agents (e.g. refinery with max_active_sessions=1)
#      where the handoff writes `assignee=<qualified-target>`.
#   2. Beads with assignee equal to a POOL SESSION NAME of this target
#      (format `<binding-prefix>__<agent-base>-<session-id>`). Multi-instance
#      pool members (e.g. polecat-3) claim work using their session name,
#      NOT the qualified pool name — so set (1)'s exact-match predicate
#      misses every claimed bead. Counting these tells the supervisor that
#      a polecat slot is doing real work and must not be freed.
#   3. Routed unassigned ready beads (the classic pool-demand case).
#
# The three sets are disjoint by construction:
#   - (1) requires exact assignee match against `<rig>/<bp>.<agent>`
#   - (2) requires assignee prefix `<bp>__<agent>-` (different separator)
#   - (3) requires --unassigned

# Parse target `<rig>/<binding-prefix>.<agent-base>` to derive the session-
# name prefix used by pool members.
after_slash="${target#*/}"             # gastown-beads-lite.polecat
binding_prefix="${after_slash%.*}"     # gastown-beads-lite
agent_base="${after_slash##*.}"        # polecat
session_prefix="${binding_prefix}__${agent_base}-"

assigned_json="$("$bd_cli" list --status open,in_progress --assignee="$target" --exclude-type=epic --json --limit=0)"
all_open_json="$("$bd_cli" list --status open,in_progress --exclude-type=epic --json --limit=0)"
routed_json="$("$bd_cli" ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json --limit=0)"

assigned=$(printf '%s\n' "$assigned_json" | jq 'length')
session_assigned=$(printf '%s\n' "$all_open_json" | jq --arg p "$session_prefix" '[.[] | select(.assignee // "" | startswith($p))] | length')
routed=$(printf '%s\n' "$routed_json" | jq 'length')

printf '%d\n' "$((assigned + session_assigned + routed))"
