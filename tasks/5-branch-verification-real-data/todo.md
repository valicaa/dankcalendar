# Issue #5 — tooling: branch verification runs against real calendar data

Owner decisions (issue comment 2026-09-25): service restart OK; dev instance offline-only.

- [ ] Design + implement an isolated dev-instance procedure (scratch XDG dirs seeded from a copy, offline-only, clean stop that always leaves `dcal.service` active), run for real once; update `verify-change` and `new-feature` phase 4 — dcal-architect
- [ ] Scenario 1: dummy-migration scratch worktree (never committed to the branch) → real `dankcal.db` checksum + goose version unchanged — dcal-verifier
- [ ] Scenario 2: no dev `dcal` left (`pgrep`), `systemctl --user is-active dcal` → `active` — dcal-verifier
- [ ] Scenario 3 + offline-only: fresh-Bash-call procedure, no remote calendar reached — dcal-verifier
- [ ] Review of the diff (M) — dcal-reviewer
- [ ] Fresh-agent literal walkthrough of the updated docs — dcal-scout
- [ ] PR opened (6.2), checkout back on `master` — dcal-builder
