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
BEADS_DIR="${BEADS_DIR:-$CITY_ROOT/.beads}"
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

"$bd_bin" --db "$DB_FILE" "$@" 9>&-
