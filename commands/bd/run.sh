#!/usr/bin/env bash
set -euo pipefail

bd_bin="${GC_BEADS_LITE_BD:-${BEADS_LITE_BD:-}}"
if [ -z "$bd_bin" ]; then
  bd_bin="$(command -v bd-lite || true)"
fi

if [ -z "$bd_bin" ] || [ ! -x "$bd_bin" ]; then
  echo "gc gastown-beads-lite bd: bd-lite not found in PATH" >&2
  exit 127
fi

CITY_ROOT="${GC_CITY_ROOT:-${GC_CITY_PATH:-${GC_CITY:-$(pwd)}}}"
EXPLICIT_BEADS_DIR="${BEADS_DIR:-}"

has_db_arg() {
  for arg in "$@"; do
    case "$arg" in
      --db|--db=*)
        return 0
        ;;
    esac
  done
  return 1
}

first_command() {
  local skip_next=0
  local arg

  for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi

    case "$arg" in
      --actor|--db|-C|--directory)
        skip_next=1
        ;;
      --actor=*|--db=*|--directory=*)
        ;;
      --json|--profile|-q|--quiet|--readonly|-v|--verbose)
        ;;
      -*)
        ;;
      *)
        printf '%s\n' "$arg"
        return
        ;;
    esac
  done
}

command_routes_by_id() {
  case "$1" in
    assign|children|close|comment|comments|defer|delete|dep|duplicate|duplicates|epic|get|graph|label|link|note|priority|promote|rename|reopen|show|supersede|tag|undefer|update)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

first_bead_id_arg() {
  local skip_next=0
  local arg

  for arg in "$@"; do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi

    case "$arg" in
      --actor|--db|-C|--directory|--assignee|-a|--status|-s|--type|-t|--priority|-p|--metadata|--set-metadata|--unset-metadata|--title|--description|-d|--notes|--reason|-r)
        skip_next=1
        continue
        ;;
      --*=*)
        ;;
      -*)
        continue
        ;;
    esac

    if [[ "$arg" =~ ^[[:alpha:]][[:alnum:]_]*-[[:alnum:]][[:alnum:]_.-]*$ ]]; then
      printf '%s\n' "$arg"
      return
    fi
  done
}

store_root_for_prefix() {
  local prefix="$1"
  local json

  if ! command -v gc >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  json="$(cd "$CITY_ROOT" && gc rig list --json 2>/dev/null)" || return 1
  printf '%s\n' "$json" | jq -r --arg prefix "$prefix" '
    .rigs[]
    | select(.prefix == $prefix)
    | .path
  ' | sed -n '1p'
}

if has_db_arg "$@"; then
  export BD_EXPORT_AUTO=false
  export BD_NAME=bd
  exec "$bd_bin" "$@"
fi

STORE_ROOT="$CITY_ROOT"
cmd="$(first_command "$@" || true)"
if [ -z "$EXPLICIT_BEADS_DIR" ] && [ -n "$cmd" ] && command_routes_by_id "$cmd"; then
  route_id="$(first_bead_id_arg "$@" || true)"
  if [ -n "$route_id" ]; then
    route_prefix="${route_id%%-*}"
    route_root="$(store_root_for_prefix "$route_prefix" || true)"
    if [ -n "$route_root" ]; then
      STORE_ROOT="$route_root"
    fi
  fi
fi

BEADS_DIR="${EXPLICIT_BEADS_DIR:-$STORE_ROOT/.beads}"
DB_FILE="$BEADS_DIR/beads.sqlite3"

mkdir -p "$BEADS_DIR"
chmod 700 "$BEADS_DIR" 2>/dev/null || true

if command -v flock >/dev/null 2>&1; then
  exec 9>"$BEADS_DIR/gc-beads-lite.lock"
  flock 9
fi

export BEADS_DIR
export BD_EXPORT_AUTO=false
export BD_NAME=bd

if [ "${GC_BEADS_LITE_ROUTE_DEBUG:-}" = "1" ]; then
  echo "gc gastown-beads-lite bd: store=$BEADS_DIR" >&2
fi

"$bd_bin" --db "$DB_FILE" "$@" 9>&-
