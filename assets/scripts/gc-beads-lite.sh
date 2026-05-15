#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "gc-beads-lite: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"
}

resolve_bd_lite() {
  if [ -n "${GC_BEADS_LITE_BD:-}" ] && [ -x "${GC_BEADS_LITE_BD:-}" ]; then
    printf '%s\n' "$GC_BEADS_LITE_BD"
    return
  fi
  if [ -n "${BEADS_LITE_BD:-}" ] && [ -x "${BEADS_LITE_BD:-}" ]; then
    printf '%s\n' "$BEADS_LITE_BD"
    return
  fi
  if command -v bd-lite >/dev/null 2>&1; then
    command -v bd-lite
    return
  fi
  die "bd-lite not found in PATH"
}

reset_paths() {
  STORE_ROOT="${1:-${GC_STORE_ROOT:-${GC_CITY_PATH:-${GC_CITY_ROOT:-${GC_CITY:-${PWD}}}}}}"
  PREFIX="${2:-${GC_BEADS_PREFIX:-te}}"
  BEADS_DIR_PATH="${STORE_ROOT}/.beads"
  DB_FILE="${BEADS_DIR_PATH}/beads.sqlite3"
}

read_payload() {
  local payload
  payload="$(cat)"
  if [ -z "$(printf '%s' "$payload" | tr -d '[:space:]')" ]; then
    payload='{}'
  fi
  printf '%s' "$payload"
}

jq_payload() {
  local payload="$1"
  local filter="$2"
  printf '%s' "$payload" | jq -r "$filter"
}

json_has() {
  local payload="$1"
  local filter="$2"
  printf '%s' "$payload" | jq -e "$filter" >/dev/null
}

bd_cmd() {
  BD_EXPORT_AUTO=false BEADS_DIR="$BEADS_DIR_PATH" "$BD_BIN" --db "$DB_FILE" "$@" 9>&-
}

bd_json() {
  BD_EXPORT_AUTO=false BEADS_DIR="$BEADS_DIR_PATH" "$BD_BIN" --db "$DB_FILE" --json "$@" 9>&-
}

ensure_store() {
  mkdir -p "$BEADS_DIR_PATH"
  chmod 700 "$BEADS_DIR_PATH" 2>/dev/null || true

  if [ -f "$BEADS_DIR_PATH/metadata.json" ]; then
    local backend
    backend="$(jq -r '.backend // empty' "$BEADS_DIR_PATH/metadata.json" 2>/dev/null || true)"
    if [ "$backend" != "sqlite" ]; then
      die "$BEADS_DIR_PATH is not a beads-lite SQLite store (backend=${backend:-unknown})"
    fi
  fi

  if [ ! -f "$DB_FILE" ]; then
    bd_cmd init --quiet --prefix "$PREFIX" >/dev/null
  fi

  bd_cmd config set types.custom "$CUSTOM_TYPES" >/dev/null 2>&1 || true
}

health_store() {
  ensure_store
  bd_json list --flat --all --limit 1 >/dev/null
  printf '{"ok":true}\n'
}

JQ_DEFS='
def gc_status:
  if (.status // "") == "closed" then "closed"
  elif (.status // "") == "in_progress" then "in_progress"
  else "open" end;
def gc_priority:
  if has("priority") and .priority != null then (try (.priority | tonumber) catch null) else null end;
def gc_needs:
  if (.needs? | type) == "array" then .needs
  elif (.dependencies? | type) == "array" then [.dependencies[] | (.depends_on_id // .id // empty)]
  else [] end;
def gc_norm: {
  id: (.id // ""),
  title: (.title // ""),
  status: gc_status,
  type: (.type // .issue_type // "task"),
  priority: gc_priority,
  created_at: (.created_at // "0001-01-01T00:00:00Z"),
  assignee: (.assignee // ""),
  from: (.from // .sender // .metadata.from? // ""),
  parent_id: (.parent_id // .parent // ""),
  ref: (.ref // .external_ref // ""),
  needs: gc_needs,
  description: (.description // ""),
  labels: (.labels // []),
  metadata: (.metadata // {})
};'

normalize_one() {
  jq -c "$JQ_DEFS gc_norm"
}

normalize_first() {
  jq -c "$JQ_DEFS (if type == \"array\" then .[0] else . end) | gc_norm"
}

normalize_array() {
  jq -c "$JQ_DEFS if type == \"array\" then map(gc_norm) else [gc_norm] end"
}

append_metadata_args() {
  local payload="$1"
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    args+=(--set-metadata "$line")
  done < <(printf '%s' "$payload" | jq -r '.metadata // {} | to_entries[] | "\(.key)=\(.value | if type == "string" then . else tostring end)"')
}

op="${1:-}"
[ -n "$op" ] || die "missing operation"
shift || true

require_cmd jq
BD_BIN="$(resolve_bd_lite)"
CUSTOM_TYPES="${GC_BEADS_LITE_TYPES:-molecule,convoy,message,event,gate,merge-request,agent,role,rig,session,spec,convergence}"
reset_paths
mkdir -p "$BEADS_DIR_PATH"
chmod 700 "$BEADS_DIR_PATH" 2>/dev/null || true

if command -v flock >/dev/null 2>&1; then
  exec 9>"$BEADS_DIR_PATH/gc-beads-lite.lock"
  flock 9
fi

case "$op" in
  init)
    if [ "${1:-}" != "" ]; then
      reset_paths "$1" "${2:-${GC_BEADS_PREFIX:-te}}"
    fi
    ensure_store
    ;;

  start|recover|ensure-ready|health|probe)
    health_store
    ;;

  stop|shutdown)
    ;;

  create)
    ensure_store
    payload="$(read_payload)"
    title="$(jq_payload "$payload" '.title // empty')"
    [ -n "$title" ] || die "create payload missing title"
    typ="$(jq_payload "$payload" '.type // "task"')"
    args=(create "$title" -t "$typ")
    if json_has "$payload" 'has("priority") and .priority != null'; then
      args+=(-p "$(jq_payload "$payload" '.priority')")
    fi
    description="$(jq_payload "$payload" '.description // empty')"
    [ -n "$description" ] && args+=(--description "$description")
    assignee="$(jq_payload "$payload" '.assignee // empty')"
    [ -n "$assignee" ] && args+=(--assignee "$assignee")
    parent_id="$(jq_payload "$payload" '.parent_id // empty')"
    [ -n "$parent_id" ] && args+=(--parent "$parent_id")
    ref="$(jq_payload "$payload" '.ref // empty')"
    [ -n "$ref" ] && args+=(--external-ref "$ref")
    labels="$(jq_payload "$payload" '(.labels // []) | join(",")')"
    [ -n "$labels" ] && args+=(--labels "$labels")
    needs="$(jq_payload "$payload" '(.needs // []) | join(",")')"
    [ -n "$needs" ] && args+=(--deps "$needs")
    metadata="$(printf '%s' "$payload" | jq -c '(.metadata // {}) as $m | if ((.from // "") != "") and (($m.from // "") == "") then $m + {from: .from} else $m end')"
    [ "$metadata" != "{}" ] && args+=(--metadata "$metadata")
    created="$(bd_json "${args[@]}")"
    created_id="$(printf '%s' "$created" | jq -r '.id // empty')"
    [ -n "$created_id" ] || printf '%s' "$created" | normalize_one
    bd_json show "$created_id" | normalize_first
    ;;

  get)
    ensure_store
    id="${1:-}"
    [ -n "$id" ] || die "usage: get <id>"
    bd_json show "$id" | normalize_first
    ;;

  update)
    ensure_store
    id="${1:-}"
    [ -n "$id" ] || die "usage: update <id>"
    payload="$(read_payload)"
    args=(update "$id")
    if json_has "$payload" 'has("title") and .title != null'; then
      args+=(--title "$(jq_payload "$payload" '.title')")
    fi
    if json_has "$payload" 'has("status") and .status != null'; then
      args+=(--status "$(jq_payload "$payload" '.status')")
    fi
    if json_has "$payload" 'has("type") and .type != null'; then
      args+=(-t "$(jq_payload "$payload" '.type')")
    fi
    if json_has "$payload" 'has("priority") and .priority != null'; then
      args+=(-p "$(jq_payload "$payload" '.priority')")
    fi
    if json_has "$payload" 'has("description") and .description != null'; then
      args+=(--description "$(jq_payload "$payload" '.description')")
    fi
    if json_has "$payload" 'has("parent_id") and .parent_id != null'; then
      args+=(--parent "$(jq_payload "$payload" '.parent_id')")
    fi
    if json_has "$payload" 'has("assignee") and .assignee != null'; then
      args+=(--assignee "$(jq_payload "$payload" '.assignee')")
    fi
    while IFS= read -r label; do
      [ -n "$label" ] && args+=(--add-label "$label")
    done < <(printf '%s' "$payload" | jq -r '.labels[]?')
    while IFS= read -r label; do
      [ -n "$label" ] && args+=(--remove-label "$label")
    done < <(printf '%s' "$payload" | jq -r '.remove_labels[]?')
    append_metadata_args "$payload"
    bd_cmd "${args[@]}" >/dev/null
    ;;

  close)
    ensure_store
    id="${1:-}"
    [ -n "$id" ] || die "usage: close <id>"
    bd_cmd close "$id" --force --reason "closed by gascity" >/dev/null
    ;;

  reopen)
    ensure_store
    id="${1:-}"
    [ -n "$id" ] || die "usage: reopen <id>"
    bd_cmd reopen "$id" >/dev/null
    ;;

  list)
    ensure_store
    args=(list --flat)
    has_status=0
    limit=0
    for arg in "$@"; do
      case "$arg" in
        --status=*)
          has_status=1
          args+=(--status "${arg#--status=}")
          ;;
        --assignee=*)
          args+=(--assignee "${arg#--assignee=}")
          ;;
        --type=*)
          args+=(-t "${arg#--type=}")
          ;;
        --limit=*)
          limit="${arg#--limit=}"
          ;;
      esac
    done
    [ "$has_status" -eq 0 ] && args+=(--all)
    args+=(--limit "$limit")
    bd_json "${args[@]}" | normalize_array
    ;;

  ready)
    ensure_store
    bd_json ready --limit 0 | normalize_array
    ;;

  children)
    ensure_store
    id="${1:-}"
    [ -n "$id" ] || die "usage: children <id>"
    bd_json list --flat --all --limit 0 --parent "$id" | normalize_array
    ;;

  list-by-label)
    ensure_store
    label="${1:-}"
    limit="${2:-0}"
    [ -n "$label" ] || die "usage: list-by-label <label> [limit]"
    bd_json list --flat --all --limit "$limit" --label "$label" | normalize_array
    ;;

  set-metadata)
    ensure_store
    id="${1:-}"
    key="${2:-}"
    [ -n "$id" ] && [ -n "$key" ] || die "usage: set-metadata <id> <key>"
    value="$(cat)"
    bd_cmd update "$id" --set-metadata "$key=$value" >/dev/null
    ;;

  delete)
    ensure_store
    id=""
    for arg in "$@"; do
      [ "$arg" = "--force" ] && continue
      id="$arg"
    done
    [ -n "$id" ] || die "usage: delete [--force] <id>"
    bd_cmd delete --force "$id" >/dev/null
    ;;

  dep-add)
    ensure_store
    issue_id="${1:-}"
    depends_on="${2:-}"
    dep_type="${3:-blocks}"
    [ -n "$issue_id" ] && [ -n "$depends_on" ] || die "usage: dep-add <issue-id> <depends-on-id> [type]"
    bd_cmd dep add "$issue_id" "$depends_on" --type "$dep_type" >/dev/null
    ;;

  dep-remove)
    ensure_store
    issue_id="${1:-}"
    depends_on="${2:-}"
    [ -n "$issue_id" ] && [ -n "$depends_on" ] || die "usage: dep-remove <issue-id> <depends-on-id>"
    bd_cmd dep remove "$issue_id" "$depends_on" >/dev/null
    ;;

  dep-list)
    ensure_store
    id="${1:-}"
    direction="${2:-down}"
    [ -n "$id" ] || die "usage: dep-list <id> [direction]"
    bd_json dep list "$id" --direction "$direction" | jq -c --arg id "$id" --arg direction "$direction" '
      if type != "array" then []
      else
        map(
          if has("issue_id") and has("depends_on_id") then
            {issue_id: .issue_id, depends_on_id: .depends_on_id, type: (.type // .dependency_type // "blocks")}
          elif $direction == "up" then
            {issue_id: (.id // .issue_id // ""), depends_on_id: $id, type: (.type // .dependency_type // "blocks")}
          else
            {issue_id: $id, depends_on_id: (.id // .depends_on_id // ""), type: (.type // .dependency_type // "blocks")}
          end
        )
        | map(select(.issue_id != "" and .depends_on_id != ""))
      end'
    ;;

  *)
    exit 2
    ;;
esac
