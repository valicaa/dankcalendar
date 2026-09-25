# Issue #5 — tooling: branch verification runs against real calendar data

Owner decisions (issue comment 2026-09-25): service restart OK; dev instance offline-only.

- [x] Design + implement an isolated dev-instance procedure (scratch XDG dirs seeded from a copy, offline-only, clean stop that always leaves `dcal.service` active), run for real once; update `verify-change` and `new-feature` phase 4 — dcal-architect (b9b0ee2…9472ca7, 5 fix rounds; `new-feature` phase 4 unchanged, it only points at `verify-change` section 4)
- [x] Scenario 1: dummy-migration scratch worktree (never committed to the branch) → real `dankcal.db` checksum + goose version unchanged — dcal-verifier (3 walkthroughs, last at 46fab21)
- [x] Scenario 2: no dev `dcal` left (`pgrep`), `systemctl --user is-active dcal` → `active` — dcal-verifier
- [x] Scenario 3 + offline-only: fresh-Bash-call procedure, no remote calendar reached — dcal-verifier
- [x] Review of the diff (M) — dcal-reviewer (5 rounds; final: pass, no blockers)
- [x] Fresh-agent literal walkthrough of the updated docs — dcal-verifier (took the scout's slot: it had to run the procedure, not only read it)
- [ ] PR opened (6.2), checkout back on `master` — dcal-builder

## Result

`.claude/tools/dev-instance.sh` runs a branch as a transient `dankcal-dev` systemd user unit on a
scratch copy of the real data (`PrivateNetwork=yes` + a loopback-only guard; refuses when a
Secret Service or EDS is on the shared session bus). It conflicts with `dcal.service`, is ordered
after it, and restarts it on every exit path. `stop` compares the real DB's sha256 and deletes the
copy. `verify-change` section 4, `dcal-verifier`, `dcal-recipes` step 8 and CLAUDE.md now point at it.

Known follow-up (not blocking): with `sqlite3` missing, `start` refuses correctly but blames an
Evolution account.
