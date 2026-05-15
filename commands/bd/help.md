Run bd-lite against the city-level SQLite beads store.

Commands that name a bead ID are routed by prefix across the city and
registered rigs. For example, `show az-123` runs against the rig whose prefix
is `az`. Commands without an ID use the city-level store.

Examples:

    gc gastown-beads-lite bd list
    gc gastown-beads-lite bd create "New task" -t task
    gc gastown-beads-lite bd show te-abc
    gc gastown-beads-lite bd show az-123
