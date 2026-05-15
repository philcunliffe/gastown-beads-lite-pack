#!/bin/sh
# Idempotently create a Gas City agent worktree for a rig checkout.
#
# Usage:
#   gc-beads-lite-worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]

set -eu

die() {
    echo "gc-beads-lite-worktree-setup: $*" >&2
    exit 1
}

RIG_ROOT="${1:?usage: gc-beads-lite-worktree-setup.sh <rig-root> <target-dir> <agent-name> [--sync]}"
TARGET_DIR="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
SYNC="${4:-}"

[ -d "$RIG_ROOT/.git" ] || [ -f "$RIG_ROOT/.git" ] || die "rig root is not a git checkout: $RIG_ROOT"

case "$TARGET_DIR" in
    /*)
        WT="$TARGET_DIR"
        ;;
    *)
        CITY_ROOT="${GC_CITY_PATH:-${GC_CITY_ROOT:-${GC_CITY:-$(pwd)}}}"
        WT="$CITY_ROOT/$TARGET_DIR"
        ;;
esac

sync_worktree() {
    [ "$SYNC" = "--sync" ] || return 0
    if ! git -C "$WT" remote get-url origin >/dev/null 2>&1; then
        return 0
    fi
    git -C "$WT" fetch origin >/dev/null 2>&1 || true
    git -C "$WT" pull --rebase >/dev/null 2>&1 || true
}

branch_name() {
    hash=$(printf '%s' "$WT" | git -C "$RIG_ROOT" hash-object --stdin | cut -c1-12)
    printf 'gc-%s-%s' "$AGENT" "$hash"
}

if [ -d "$WT/.git" ] || [ -f "$WT/.git" ]; then
    sync_worktree
    exit 0
fi

mkdir -p "$(dirname "$WT")"
git -C "$RIG_ROOT" worktree prune >/dev/null 2>&1 || true

branch="$(branch_name)"
default_ref="$(git -C "$RIG_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$default_ref" ]; then
    default_branch="${default_ref#refs/remotes/origin/}"
    git -C "$RIG_ROOT" fetch origin "$default_branch" >/dev/null 2>&1 || true
fi

if git -C "$RIG_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" worktree add "$WT" "$branch" >/dev/null
elif [ -n "$default_ref" ]; then
    GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" worktree add "$WT" -b "$branch" "$default_ref" >/dev/null
else
    GIT_LFS_SKIP_SMUDGE=1 git -C "$RIG_ROOT" worktree add "$WT" -b "$branch" >/dev/null
fi

mkdir -p "$WT/.beads"
printf '%s\n' "$RIG_ROOT/.beads" > "$WT/.beads/redirect"

git -C "$WT" submodule init >/dev/null 2>&1 || true

exclude="$(git -C "$WT" rev-parse --git-path info/exclude)"
case "$exclude" in
    /*) ;;
    *) exclude="$WT/$exclude" ;;
esac
mkdir -p "$(dirname "$exclude")"
touch "$exclude"

marker="# Gas City worktree infrastructure (local excludes)"
if ! grep -qF "$marker" "$exclude" 2>/dev/null; then
    [ ! -s "$exclude" ] || printf '\n' >> "$exclude"
    printf '%s\n' "$marker" >> "$exclude"
fi

append_exclude() {
    pattern="$1"
    grep -qxF "$pattern" "$exclude" 2>/dev/null || printf '%s\n' "$pattern" >> "$exclude"
}

append_exclude ".beads/redirect"
append_exclude ".beads/hooks/"
append_exclude ".beads/formulas/"
append_exclude ".runtime/"
append_exclude ".logs/"
append_exclude "worktrees/"
append_exclude "__pycache__/"
append_exclude ".claude/"
append_exclude ".codex/"
append_exclude ".gemini/"
append_exclude ".opencode/"
append_exclude ".github/hooks/"
append_exclude ".github/copilot-instructions.md"
append_exclude "state.json"

sync_worktree
