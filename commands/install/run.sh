#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "gc gastown-beads-lite install: $*" >&2
  exit 1
}

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pack_dir="${GC_PACK_DIR:-$(CDPATH= cd -- "$script_dir/../.." && pwd)}"
city_root="${GC_CITY_PATH:-${GC_CITY_ROOT:-$(pwd)}}"
copy_rigs=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-rigs)
      copy_rigs=0
      shift
      ;;
    -h|--help)
      sed -n '1,120p' "$script_dir/help.md"
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

formulas_src="$pack_dir/formulas"
[ -d "$formulas_src" ] || die "formula directory not found: $formulas_src"

copy_formulas() {
  local root="$1"
  local label="$2"
  local dest="$root/.beads/formulas"
  local count=0

  mkdir -p "$dest"
  for formula in "$formulas_src"/*.formula.toml; do
    [ -e "$formula" ] || continue
    dest_file="$dest/$(basename "$formula")"
    if [ -L "$dest_file" ]; then
      rm "$dest_file"
    fi
    cp "$formula" "$dest_file"
    count=$((count + 1))
  done

  printf '%s: copied %s formulas to %s\n' "$label" "$count" "$dest"
}

copy_formulas "$city_root" "city"

if [ "$copy_rigs" -eq 1 ]; then
  if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    rig_paths="$(cd "$city_root" && gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.hq != true) | .path')"
    if [ -n "$rig_paths" ]; then
      while IFS= read -r rig_path; do
        [ -n "$rig_path" ] || continue
        copy_formulas "$rig_path" "rig $(basename "$rig_path")"
      done <<EOF
$rig_paths
EOF
    fi
  else
    echo "rig formula install skipped: gc or jq not found"
  fi
fi

provider="$pack_dir/assets/scripts/gc-beads-lite.sh"
echo
echo "Provider script:"
echo "  exec:$provider"
echo
echo "Default sling target shape:"
echo "  <rig>/gastown-beads-lite.polecat"
echo
echo "Refinery target shape:"
echo "  <rig>/gastown-beads-lite.refinery"
