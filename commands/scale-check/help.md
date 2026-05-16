Count work that requires a session for a gastown-beads-lite target.

Usage:

    gc gastown-beads-lite scale-check <qualified-target> [scope-root]

Returns the sum of:

- Beads assigned directly to the target (status open or in_progress). This
  covers refineries that have been handed work via `--assignee=<refinery>`
  after a polecat completes implementation.
- Routed-to-target ready beads with no assignee. This covers the polecat
  pool case where work waits unassigned for a polecat to claim it.

The two sets are disjoint by construction, so the sum reflects total work
the supervisor should make sessions available for.

This command is used by the polecat and refinery `scale_check` hooks.
