# Agent Notes

This repository is the source of truth for the `gastown-beads-lite` Gas City
pack. Treat city checkouts such as `/Users/phil/testcity` as integration
harnesses, not as the place to make lasting pack changes.

## Development Loop

1. Edit this repo.
2. Point a test city at this repo, usually by symlink or local `packs/` copy.
3. Validate in the test city.
4. Commit and push from this repo.

Avoid developing long-term inside a city and porting later. That usually leaves
behind hardcoded city paths, stale formulas, or prompt drift.

## Pack Goals

- Use `beads-lite` SQLite stores instead of normal Dolt-backed `bd`.
- Keep the setup small enough for personal coding cities.
- Preserve the useful Gastown coding workflow shape: mayor, rig polecats, rig
  witness.
- Do not import the normal `bd`/Dolt pack, deacon, refinery, or Dolt
  maintenance roles unless they have been made Dolt-free first.

## Current Roles

- `mayor`: city-scoped coordinator. Prompt must stay generic and must not name
  a specific rig.
- `polecat`: rig-scoped coding worker pool. Dispatch target is
  `<rig>/gastown-beads-lite.polecat`.
- `witness`: rig-scoped oversight/escalation role.

When adding more Gastown agents, inspect their prompts, formulas, orders, and
scripts for Dolt, refinery, `gc bd`, and normal `bd` assumptions. Port only the
parts that make sense with beads-lite.

## Portability Rules

- Never hardcode city-local paths such as `/Users/phil/testcity`.
- Do not rely on `{{.ConfigDir}}` in agent env or prompt examples for wrapper
  paths. It can render empty in some Gas City prompt/config contexts.
- In command/order scripts, resolve the pack root from `GC_PACK_DIR` with a
  script-location fallback.
- In prompts, use generic rig names like `<rig>` or template variables such as
  `{{ .RigName }}`.
- Keep repo files ASCII unless there is a clear reason to match existing
  non-ASCII content.

## Beads-Lite Wiring

The important distinction:

- `bd` on a user's shell PATH may be regular beads.
- `assets/bin/bd` is this pack's wrapper and must execute `bd-lite`.
- Agent prompts should call `gc gastown-beads-lite bd ...` explicitly. Do not
  depend on session `PATH` making bare `bd` resolve to this pack's wrapper.
- Controller-side routing must call `gc gastown-beads-lite bd` or the wrapper
  explicitly, not a bare `bd`.
- The `gc gastown-beads-lite bd` command routes ID-based commands by prefix
  using `gc rig list --json`; commands without an ID stay on the city store.
- ID-based commands like `show az-123` and `update az-123` can omit `BEADS_DIR`
  when city-root routing is available.
- For no-ID/store-scoped commands in prompts and sling queries, prefix the
  command with `BEADS_DIR=<rig-root>/.beads` so `list`, `ready`, `formula`,
  `create`, and `mol seed` use the rig store. It is also fine to keep
  `BEADS_DIR` on ID-based examples for deterministic agent behavior from
  worktrees.

The wrapper honors:

- `BEADS_DIR`: uses `$BEADS_DIR/beads.sqlite3` and serializes with
  `$BEADS_DIR/gc-beads-lite.lock`.
- `GC_BEADS_LITE_BD` or `BEADS_LITE_BD`: explicit path to the `bd-lite` binary.
- `BD_EXPORT_AUTO=false` and `BD_NAME=bd`: keep agent-facing examples stable.

The exec provider is `assets/scripts/gc-beads-lite.sh`. Its default store root
should resolve from `GC_STORE_ROOT`, `GC_CITY_PATH`, `GC_CITY_ROOT`, `GC_CITY`,
then `PWD`, in that order.

## Commands And Scripts

- `commands/bd/run.sh` backs `gc gastown-beads-lite bd`. It finds `bd-lite`
  from `GC_BEADS_LITE_BD`, `BEADS_LITE_BD`, then `PATH`; sets
  `BD_EXPORT_AUTO=false` and `BD_NAME=bd`; serializes access with
  `.beads/gc-beads-lite.lock`; and routes ID-based commands such as `show`,
  `update`, `close`, and `delete` to the matching rig store by comparing the
  bead ID prefix with `gc rig list --json`. If `BEADS_DIR` is already set or a
  `--db` argument is supplied, it does not do prefix routing.
- `assets/scripts/gc-beads-lite.sh` is the Gas City beads exec provider used by
  `city.toml [beads].provider`. It implements the provider operations against a
  beads-lite SQLite DB and normalizes rows into the shape Gas City expects.
- `assets/scripts/gc-beads-lite-scale-check.sh` backs
  `gc gastown-beads-lite scale-check`. It counts unassigned ready beads whose
  `metadata.gc.routed_to` matches the qualified target. Pass the rig root as the
  second argument so it sets `BEADS_DIR=<rig-root>/.beads`.
- `assets/scripts/gc-beads-lite-work-query.sh` backs
  `gc gastown-beads-lite work-query`. It first returns work assigned to the
  current session, then ready work assigned to the session, then unassigned
  ready work routed to the qualified target. Persistent/non-ephemeral sessions
  do not pull new routed work from the shared pool.
- `commands/install/run.sh` copies bundled `*.formula.toml` files into the city
  and rig `.beads/formulas` directories. It removes stale symlink destinations
  before copying so old local pack links do not cause writes into the wrong
  source tree.
- `scripts/link-into-city.sh <city-path> [pack-link-name]` is a convenience
  integrator for local development. It creates or updates
  `<city>/packs/<pack-link-name>` as a symlink to this repo, prints the required
  `pack.toml` and `city.toml` snippets, and, once the city config resolves,
  runs `gc gastown-beads-lite install`, `gc rig list`, and a dry-run sling
  smoke check for the first non-HQ rig.

## Formulas

Bundled formulas live in `formulas/*.formula.toml`; beads-lite discovers
`.formula.toml` files, not the Gas City core pack's bare `.toml` names.

After formula edits, run:

```sh
gc gastown-beads-lite install
```

That copies formulas into the city `.beads/formulas` directory and all
registered rig `.beads/formulas` directories.

Do not make `mol-polecat-commit` the automatic `default_sling_formula` until
the Gas City molecule attachment path is proven compatible with beads-lite.
During testcity work, formula attachment collided with beads-lite
parent-child dependency validation. The current safe path is raw `gc sling`
routing plus the polecat prompt telling the worker to read:

```sh
BEADS_DIR=<rig-root>/.beads gc gastown-beads-lite bd formula show mol-polecat-commit
```

Formula bodies may still contain generic `bd ...` examples because they are
workflow recipes. Prompt text for agents must say to translate those examples to
`gc gastown-beads-lite bd ...`, adding `BEADS_DIR=<rig-root>/.beads` for
commands that do not name a bead ID or whenever deterministic rig-store
selection matters. If a formula is intended to be copied directly into a shell
rather than read by an agent, rewrite its examples to the explicit wrapper form
first.

## Dispatch Model

For new coding work:

```sh
gc sling <rig>/gastown-beads-lite.polecat "task title"
```

For existing rig beads:

```sh
gc sling <rig>/gastown-beads-lite.polecat <bead-id>
```

The polecat `sling_query` writes:

```text
metadata.gc.routed_to=<rig>/gastown-beads-lite.polecat
```

The scale and work query scripts look for unassigned ready beads with that
metadata. They also first prefer already assigned `in_progress` or ready work
for the current session.

## Validation Checklist

From this repo:

```sh
bash -n assets/bin/bd assets/scripts/*.sh commands/*/run.sh doctor/*/run.sh
rg -n "/Users/phil/testcity|gc beads-lite|<rig>/witness|mol-polecat-work" .
```

From a test city:

```sh
gc config show
gc rig list
gc status
gc prime mayor
gc gastown-beads-lite install
gc gastown-beads-lite bd show <rig-bead-id>
gc sling <rig>/gastown-beads-lite.polecat --dry-run "dispatch smoke"
```

For a throwaway beads-lite store:

```sh
GC_CITY_PATH=/tmp/gbl-smoke assets/scripts/gc-beads-lite.sh init /tmp/gbl-smoke zz
GC_CITY_PATH=/tmp/gbl-smoke assets/scripts/gc-beads-lite.sh health
BEADS_DIR=/tmp/gbl-smoke/.beads assets/bin/bd formula list
BEADS_DIR=/tmp/gbl-smoke/.beads assets/bin/bd mol seed mol-polecat-commit --var issue=zz-smoke
```

## Known Test City Context

`/Users/phil/testcity` was the original integration city. It used a rig named
`azworld` with prefix `az`, but pack prompts must not assume that rig exists.

The GitHub repo for this pack is:

```text
https://github.com/philcunliffe/gastown-beads-lite-pack
```
