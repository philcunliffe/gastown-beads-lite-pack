#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "link-into-city: $*" >&2
  exit 1
}

city="${1:-}"
[ -n "$city" ] || die "usage: scripts/link-into-city.sh <city-path> [pack-link-name]"

pack_link_name="${2:-gastown-beads-lite-pack}"
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
pack_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"
city="$(CDPATH= cd -- "$city" && pwd)"

mkdir -p "$city/packs"
ln -sfn "$pack_dir" "$city/packs/$pack_link_name"

cat <<EOF
Linked:
  $city/packs/$pack_link_name -> $pack_dir

pack.toml should include:

[imports.gastown-beads-lite]
source = "packs/$pack_link_name"

[defaults.rig.imports.gastown-beads-lite]
source = "packs/$pack_link_name"

city.toml should include:

[beads]
provider = "exec:$city/packs/$pack_link_name/assets/scripts/gc-beads-lite.sh"

For each coding rig:

default_sling_target = "<rig>/gastown-beads-lite.polecat"

[rigs.imports.gastown-beads-lite]
source = "packs/$pack_link_name"

Polecats submit merge-ready branches to:
  <rig>/gastown-beads-lite.refinery

EOF

if ! command -v gc >/dev/null 2>&1; then
  echo "gc not found; skipping validation."
  exit 0
fi

if ! (cd "$city" && gc config show >/dev/null 2>&1); then
  echo "City config does not resolve yet; update TOML as shown above, then rerun this script."
  exit 0
fi

(cd "$city" && gc gastown-beads-lite install)
(cd "$city" && gc rig list)

if command -v jq >/dev/null 2>&1; then
  first_rig="$(cd "$city" && gc rig list --json | jq -r '.rigs[] | select(.hq != true) | .name' | sed -n '1p')"
  if [ -n "$first_rig" ]; then
    (cd "$city" && gc sling "$first_rig/gastown-beads-lite.polecat" --dry-run "gastown-beads-lite dispatch smoke")
  fi
fi
