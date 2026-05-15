#!/usr/bin/env bash
# Tests for assets/scripts/gc-beads-lite-worktree-setup.sh
#
# Run from the pack root:
#   bash tests/worktree-setup.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/assets/scripts/gc-beads-lite-worktree-setup.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "FAIL: cannot find $SCRIPT" >&2
    exit 1
fi

failed=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gc-wts-test.XXXXXX")"

cleanup() {
    if [ -n "${TMP_ROOT:-}" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}
trap cleanup EXIT

new_tmp() {
    mktemp -d "$TMP_ROOT/case.XXXXXX"
}

make_rig() {
    rig="$1"
    mkdir -p "$rig"
    git -C "$rig" init -q -b main 2>/dev/null || git -C "$rig" init -q
    git -C "$rig" symbolic-ref HEAD refs/heads/main
    git -C "$rig" -c user.email=t@e.x -c user.name=t commit -q --allow-empty -m init
}

assert() {
    msg="$1"; shift
    if ! "$@"; then
        echo "  FAIL assertion: $msg" >&2
        return 1
    fi
}

run_case() {
    name="$1"
    fn="$2"
    if ( set -e; "$fn" ); then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        failed=$((failed + 1))
    fi
}

# Case 1: $WT does not exist → script creates a fresh worktree.
case_clean_dir() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    "$SCRIPT" "$rig" "$wt" test-agent
    assert "wt is a worktree" test -e "$wt/.git"
    assert "wt is a regular file (worktree pointer)" test -f "$wt/.git"
}

# Case 2: $WT/.git already exists → script is idempotent (no destructive
# changes). Drop a sentinel after the first run; second run must preserve it.
case_already_worktree() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    "$SCRIPT" "$rig" "$wt" test-agent
    touch "$wt/sentinel"
    "$SCRIPT" "$rig" "$wt" test-agent
    assert "sentinel preserved across re-run" test -f "$wt/sentinel"
}

# Case 3: Supervisor pre-populates $WT with .gc/settings.json before
# pre_start runs. Script must rescue the scaffolding, create the worktree,
# and restore the scaffolding contents (verbatim).
case_supervisor_scaffolding() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    mkdir -p "$wt/.gc"
    payload='{"hello":"world","n":42}'
    printf '%s' "$payload" > "$wt/.gc/settings.json"
    "$SCRIPT" "$rig" "$wt" test-agent
    assert "wt is now a worktree" test -e "$wt/.git"
    assert "supervisor settings.json preserved" test -f "$wt/.gc/settings.json"
    actual="$(cat "$wt/.gc/settings.json")"
    if [ "$actual" != "$payload" ]; then
        echo "  scaffolding contents diverged: got '$actual'" >&2
        return 1
    fi
}

# Case 3b: Supervisor scaffolding includes .beads/redirect, .runtime/, .logs/,
# and state.json — all of which must survive the worktree add.
case_supervisor_scaffolding_full() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    mkdir -p "$wt/.gc" "$wt/.runtime" "$wt/.logs" "$wt/.beads/hooks" "$wt/.beads/formulas"
    echo '{"a":1}' > "$wt/.gc/settings.json"
    echo "runtime-marker" > "$wt/.runtime/marker"
    echo "log-marker" > "$wt/.logs/marker"
    echo "state-marker" > "$wt/state.json"
    echo "$rig/.beads" > "$wt/.beads/redirect"
    echo "hook-marker" > "$wt/.beads/hooks/example.sh"
    echo "formula-marker" > "$wt/.beads/formulas/example.toml"
    "$SCRIPT" "$rig" "$wt" test-agent
    assert "wt is now a worktree" test -e "$wt/.git"
    assert ".gc/settings.json preserved" test -f "$wt/.gc/settings.json"
    assert ".runtime/marker preserved" test -f "$wt/.runtime/marker"
    assert ".logs/marker preserved" test -f "$wt/.logs/marker"
    assert "state.json preserved" test -f "$wt/state.json"
    assert ".beads/hooks/example.sh preserved" test -f "$wt/.beads/hooks/example.sh"
    assert ".beads/formulas/example.toml preserved" test -f "$wt/.beads/formulas/example.toml"
    assert ".beads/redirect present" test -f "$wt/.beads/redirect"
}

# Case 4: $WT contains an unknown entry → script must exit non-zero, leave
# $WT untouched, and mention the offending entry in the error.
case_unknown_contents() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    mkdir -p "$wt"
    echo "user notes" > "$wt/notes.md"
    set +e
    out="$("$SCRIPT" "$rig" "$wt" test-agent 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "  expected non-zero exit, got 0. output: $out" >&2
        return 1
    fi
    case "$out" in
        *notes.md*) ;;
        *)
            echo "  expected error to name notes.md, got: $out" >&2
            return 1
            ;;
    esac
    assert "notes.md preserved" test -f "$wt/notes.md"
    actual="$(cat "$wt/notes.md")"
    if [ "$actual" != "user notes" ]; then
        echo "  notes.md contents changed: got '$actual'" >&2
        return 1
    fi
    assert "no .git was created" eval "[ ! -e '$wt/.git' ]"
}

# Case 4b: Mix of allowlisted scaffolding AND an unknown entry. Script must
# fail without moving any files (scaffolding must remain in place).
case_unknown_with_scaffolding() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    mkdir -p "$wt/.gc"
    echo '{"a":1}' > "$wt/.gc/settings.json"
    echo "stray" > "$wt/stray.txt"
    set +e
    out="$("$SCRIPT" "$rig" "$wt" test-agent 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "  expected non-zero exit, got 0. output: $out" >&2
        return 1
    fi
    case "$out" in
        *stray.txt*) ;;
        *)
            echo "  expected error to name stray.txt, got: $out" >&2
            return 1
            ;;
    esac
    assert "scaffolding remains in place" test -f "$wt/.gc/settings.json"
    assert "stray.txt remains in place" test -f "$wt/stray.txt"
    assert "no .git was created" eval "[ ! -e '$wt/.git' ]"
}

# Case 4c: Unexpected entry inside .beads/ (e.g., .beads/issues.db) must
# also fail without modifying anything.
case_unknown_beads_subentry() {
    root="$(new_tmp)"
    rig="$root/rig"
    wt="$root/wt"
    make_rig "$rig"
    mkdir -p "$wt/.beads"
    echo "fake bead store" > "$wt/.beads/issues.db"
    set +e
    out="$("$SCRIPT" "$rig" "$wt" test-agent 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "  expected non-zero exit, got 0. output: $out" >&2
        return 1
    fi
    case "$out" in
        *.beads/issues.db*) ;;
        *)
            echo "  expected error to name .beads/issues.db, got: $out" >&2
            return 1
            ;;
    esac
    assert ".beads/issues.db remains in place" test -f "$wt/.beads/issues.db"
    assert "no .git was created" eval "[ ! -e '$wt/.git' ]"
}

run_case "clean dir creates worktree" case_clean_dir
run_case "already-a-worktree is idempotent" case_already_worktree
run_case "supervisor scaffolding (.gc/settings.json) preserved" case_supervisor_scaffolding
run_case "full supervisor scaffolding preserved" case_supervisor_scaffolding_full
run_case "unknown contents fail safe" case_unknown_contents
run_case "unknown alongside scaffolding fail safe" case_unknown_with_scaffolding
run_case "unknown .beads subentry fail safe" case_unknown_beads_subentry

echo
if [ "$failed" -gt 0 ]; then
    echo "$failed test(s) failed" >&2
    exit 1
fi
echo "All tests passed"
