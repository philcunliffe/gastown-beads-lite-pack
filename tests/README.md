# Pack tests

Lightweight shell tests for `gastown-beads-lite-pack` assets.

Run all tests from the pack root:

```bash
bash tests/worktree-setup.test.sh
```

Each test file is self-contained (no framework). Tests:

- create their own throwaway git rigs in `mktemp -d`
- print `PASS:` or `FAIL:` per case
- exit non-zero on any failure
- clean up their tempdirs in an `EXIT` trap

When adding a new test, follow the same pattern: a single executable
`bash tests/<name>.test.sh` that returns 0 on success and 1 on failure.
