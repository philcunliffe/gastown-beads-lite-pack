# gastown-beads-lite-pack

A Dolt-free Gas City pack for small coding cities that use `beads-lite`
SQLite stores.

The pack provides:

- a `gastown-beads-lite` Gas City pack
- a beads-lite exec provider script
- a `gc gastown-beads-lite bd ...` command for city-level bead CLI access
- generic mayor, polecat, refinery, and witness prompts
- rig-scoped coding dispatch through `gastown-beads-lite.polecat`
- optional refinery merge handoff through `gastown-beads-lite.refinery`
- beads-lite-compatible workflow formulas

It intentionally does not import the normal `bd`/Dolt pack, deacon, or Dolt
maintenance roles.

## Requirements

- `gc`
- `bd-lite` on `PATH`, or `GC_BEADS_LITE_BD=/path/to/bd-lite`
- `jq`

## Install In A City

Put this repository under your city's `packs/` directory, for example:

```text
<city>/packs/gastown-beads-lite-pack
```

Add the pack to `pack.toml`:

```toml
[imports.gastown-beads-lite]
source = "packs/gastown-beads-lite-pack"

[defaults.rig.imports.gastown-beads-lite]
source = "packs/gastown-beads-lite-pack"
```

Configure the beads provider in `city.toml` with the absolute path to the
provider script:

```toml
[beads]
provider = "exec:/absolute/path/to/city/packs/gastown-beads-lite-pack/assets/scripts/gc-beads-lite.sh"
```

For each coding rig, use the polecat pool as the default sling target:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"
default_sling_target = "my-rig/gastown-beads-lite.polecat"

[rigs.imports.gastown-beads-lite]
source = "packs/gastown-beads-lite-pack"
```

Then install formulas into the city and registered rig beads-lite stores:

```sh
gc gastown-beads-lite install
```

For a local checkout, `scripts/link-into-city.sh <city-path>` creates the
`packs/gastown-beads-lite-pack` symlink, prints the TOML snippets above, and
runs install/validation once the city config resolves.

## Usage

Create coding work for a rig:

```sh
gc sling my-rig/gastown-beads-lite.polecat "implement the requested change"
```

The default polecat prompt now uses the refinery handoff recipe:

```sh
BEADS_DIR=<rig-root>/.beads gc gastown-beads-lite bd formula show mol-polecat-work
```

Polecats push a feature branch and assign the original work bead to:

```text
my-rig/gastown-beads-lite.refinery
```

The on-demand refinery rebases the branch, runs configured checks, merges
directly or publishes a PR, and closes or rejects the work bead. For the older
single-agent path, use `mol-polecat-commit`.

Inspect the city-level beads-lite store:

```sh
gc gastown-beads-lite bd list
gc gastown-beads-lite bd create "city-level task"
gc gastown-beads-lite bd show <id>
```

Commands that name a bead ID route by prefix across the city and registered
rig stores, so `gc gastown-beads-lite bd show az-123` runs against the rig
whose prefix is `az`.

Inside mayor, polecat, refinery, and witness sessions, use
`gc gastown-beads-lite bd`, not bare `bd`. ID-based commands can route by
prefix. Store-scoped commands without a bead ID, such as `list`, `ready`,
`formula`, `create`, and `mol seed`, need `BEADS_DIR=<rig-root>/.beads` when
they should operate on a rig store. The agent prompts include `BEADS_DIR` on
rig examples as the deterministic form.

## Notes

`gc sling ... --on mol-polecat-work` is still optional because current Gas City
molecule attachment semantics can conflict with beads-lite parent-child
dependency validation. The safe path is raw `gc sling` routing plus the polecat
prompt telling workers to read the installed formula with
`gc gastown-beads-lite bd formula show ...`.
