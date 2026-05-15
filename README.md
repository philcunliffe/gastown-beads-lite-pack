# gastown-beads-lite-pack

A Dolt-free Gas City pack for small coding cities that use `beads-lite`
SQLite stores.

The pack provides:

- a `gastown-beads-lite` Gas City pack
- a beads-lite exec provider script
- a `gc gastown-beads-lite bd ...` command for city-level bead CLI access
- generic mayor, polecat, and witness prompts
- rig-scoped coding dispatch through `gastown-beads-lite.polecat`
- beads-lite-compatible workflow formulas

It intentionally does not import the normal `bd`/Dolt pack, refinery, deacon,
or Dolt maintenance roles.

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

Inspect the city-level beads-lite store:

```sh
gc gastown-beads-lite bd list
gc gastown-beads-lite bd create "city-level task"
gc gastown-beads-lite bd show <id>
```

Commands that name a bead ID route by prefix across the city and registered
rig stores, so `gc gastown-beads-lite bd show az-123` runs against the rig
whose prefix is `az`.

Inside mayor, polecat, and witness sessions, use `gc gastown-beads-lite bd`,
not bare `bd`. ID-based commands can route by prefix. Store-scoped commands
without a bead ID, such as `list`, `ready`, `formula`, `create`, and `mol seed`,
need `BEADS_DIR=<rig-root>/.beads` when they should operate on a rig store.
The agent prompts include `BEADS_DIR` on rig examples as the deterministic form.

## Notes

`gc sling ... --on mol-polecat-commit` is not enabled as the default dispatch
path here because current Gas City molecule attachment semantics can conflict
with beads-lite parent-child dependency validation. The polecat prompt still
uses `gc gastown-beads-lite bd formula show mol-polecat-commit` as the worker
recipe for direct commit coding work.
