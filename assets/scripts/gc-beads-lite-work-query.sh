#!/usr/bin/env bash
set -euo pipefail

target="${1:?usage: gc-beads-lite-work-query.sh <qualified-target> [scope-root]}"
scope_root="${2:-}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pack_dir="${GC_PACK_DIR:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}"
bd_cli="${GC_BEADS_LITE_WRAPPER:-$pack_dir/assets/bin/bd}"

if [ -n "$scope_root" ]; then
  export BEADS_DIR="$scope_root/.beads"
fi

emit_if_nonempty() {
  local json="$1"
  if [ -n "$json" ] && [ "$json" != "[]" ]; then
    printf '%s' "$json"
    return 0
  fi
  return 1
}

for id in "${GC_AGENT:-}" "${GC_SESSION_ID:-}" "${GC_SESSION_NAME:-}" "${GC_ALIAS:-}"; do
  [ -z "$id" ] && continue
  rows="$("$bd_cli" list --status in_progress --assignee="$id" --exclude-type=epic --json --limit=1 2>/dev/null || true)"
  emit_if_nonempty "$rows" && exit 0
done

for id in "${GC_AGENT:-}" "${GC_SESSION_ID:-}" "${GC_SESSION_NAME:-}" "${GC_ALIAS:-}"; do
  [ -z "$id" ] && continue
  rows="$("$bd_cli" ready --assignee="$id" --exclude-type=epic --json --limit=1 2>/dev/null || true)"
  emit_if_nonempty "$rows" && exit 0
done

case "${GC_SESSION_ORIGIN:-}" in
  ephemeral|"") ;;
  *)
    printf '[]'
    exit 0
    ;;
esac

rows="$("$bd_cli" ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json --limit=1 2>/dev/null || true)"
emit_if_nonempty "$rows" && exit 0
printf '[]'
