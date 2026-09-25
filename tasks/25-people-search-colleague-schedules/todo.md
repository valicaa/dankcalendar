# #25 ui: people search for colleague schedules

- [x] design + phased plan: scope/re-consent flow, Google fetch (events.list → freebusy fallback), IPC shape, overlay model, merge + day columns — dcal-architect
- [x] daemon: OAuth scope, Google people-schedule fetch, IPC method, Go tests — dcal-builder
- [ ] QML: sidebar People search + chips, overlay source in DankCalService, fade own events, busy blocks — dcal-builder
- [ ] QML: merge shared meetings, Day-view per-person columns — dcal-builder
- [ ] verify-change incl. dev-instance screenshots for scenarios 1–5 — dcal-verifier
- [ ] review against #25 + CLAUDE.md (L, provider) — dcal-reviewer
- [ ] fixes from review, re-verify — dcal-builder / dcal-verifier
- [ ] 6.1 result commit + PR body — PM
- [ ] 6.2 push, open PR, back to master — dcal-builder
