#!/usr/bin/env bash
set -euo pipefail

bd_bin="${GC_BEADS_LITE_BD:-${BEADS_LITE_BD:-}}"
if [ -z "$bd_bin" ]; then
  bd_bin="$(command -v bd-lite || true)"
fi

if [ -z "$bd_bin" ] || [ ! -x "$bd_bin" ]; then
  echo "bd-lite not found in PATH"
  echo "Install bd-lite and place it on PATH, or set GC_BEADS_LITE_BD."
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH"
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
beads_dir="$tmp/.beads"
db_file="$beads_dir/beads.sqlite3"

"$bd_bin" --db "$db_file" init --quiet --prefix zz
"$bd_bin" --db "$db_file" --json list --flat --all --limit 1 >/dev/null

backend="$(jq -r '.backend // empty' "$beads_dir/metadata.json")"
if [ "$backend" != "sqlite" ]; then
  echo "bd-lite initialized backend=$backend, expected sqlite"
  exit 2
fi

version="$("$bd_bin" --version 2>/dev/null || true)"
echo "bd-lite ${version:-ok}"
