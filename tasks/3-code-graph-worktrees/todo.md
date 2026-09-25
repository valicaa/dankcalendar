# Issue #3 — tooling: code graph unavailable in git worktrees

- [x] `graph-calls.py` (and graph memory lookups) resolve `graphify-out/` via `git rev-parse --git-common-dir` in a linked worktree; missing-graph error points at the QML-preserving refresh procedure; `code-graph` skill documents worktree behaviour and that the graph reflects `master` — dcal-builder (4 rounds: + `graph-qml.py` refuses in worktrees, local worktree graphs ignored, `--graph` for raw `graphify` commands)
- [x] Verify scenarios 1–2 in a real `git worktree add` checkout; `check-docs.py` passes — dcal-verifier (run twice; pass at 101eeef)
- [x] Fresh-agent literal walkthrough of the updated `code-graph` skill from inside a worktree — dcal-scout (4 findings → round 4)
- [ ] PR opened (6.2) — dcal-builder

## Result
Worktrees now read the main checkout's graph (`graph-calls.py` always; raw `graphify` commands via `--graph`); `graph-qml.py` refuses in a worktree; missing-graph error points at the code-graph skill. Evidence: issue #3 comments.
