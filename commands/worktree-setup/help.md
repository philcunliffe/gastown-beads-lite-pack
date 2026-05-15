Prepare a git worktree for a gastown-beads-lite agent.

Examples:

    gc gastown-beads-lite worktree-setup <rig-root> <target-dir> <agent-name> --sync

This command is intended for pack agent `pre_start` hooks. It avoids
hardcoding city-local paths and resolves relative target directories against
the city root.
