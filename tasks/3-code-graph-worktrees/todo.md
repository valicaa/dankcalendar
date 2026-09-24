# Issue #3 — tooling: code graph unavailable in git worktrees

- [ ] `graph-calls.py` (and graph memory lookups) resolve `graphify-out/` via `git rev-parse --git-common-dir` in a linked worktree; missing-graph error points at the QML-preserving refresh procedure; `code-graph` skill documents worktree behaviour and that the graph reflects `master` — dcal-builder
- [ ] Verify scenarios 1–2 in a real `git worktree add` checkout; `check-docs.py` passes — dcal-verifier
- [ ] Fresh-agent literal walkthrough of the updated `code-graph` skill from inside a worktree — dcal-scout
