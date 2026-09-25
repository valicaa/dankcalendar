# #25 ui: people search for colleague schedules

- [x] design + phased plan: scope/re-consent flow, Google fetch (events.list → freebusy fallback), IPC shape, overlay model, merge + day columns — dcal-architect
- [x] daemon: OAuth scope, Google people-schedule fetch, IPC method, Go tests — dcal-builder
- [x] QML: sidebar People search + chips, overlay source in DankCalService, fade own events, busy blocks — dcal-builder
- [x] QML: merge shared meetings, Day-view per-person columns — dcal-builder
- [x] verify-change incl. dev-instance screenshots for scenarios 1–5 — dcal-verifier
- [x] review against #25 + CLAUDE.md (L, provider) — dcal-reviewer
- [x] fixes from review, re-verify — dcal-builder / dcal-verifier
- [x] 6.1 result commit + PR body — PM
- [ ] 6.2 push, open PR, back to master — dcal-builder

## Result

Four build phases (daemon, sidebar/PeopleService, Week/Month overlay, merge + Day lanes), then five review rounds.
- The phase-1 review found that an expired token didn't lead to `reconnect`, and that rate limits and a subscribed colleague calendar were mishandled.
- The full review found three blockers: Day lanes dropping colleague events, items shown only on the day they start, and the all-day lane shift. It also found that the refetch on navigation had never worked.
- Owner decisions made mid-way: colleague events on top of the owner's on the time grid; busy-only time as a background band; the live check after deploy.
- Final verifier and reviewer passed at 270eb9f. With no people looked up, the views are byte-identical to master.
- All UI proof comes from an isolated offscreen harness driving the real views and PeopleService. The dev instance is offline, so a real Google lookup is not proven yet (the acceptance item stays open until after deploy).

Follow-ups (minor): "+N more" in the Week all-day row should be gated on `PeopleService.active`; the month-popover dim base should be `surfaceContainerHigh`; the Week all-day sort should reuse `_byStart`. For upstream: squash the history and deal with the en.json churn.

Incidents: the architect hit a session rate limit once and was resumed with nothing lost. Two briefs of mine carried the owner's time-grid rule over to list-shaped rows (Month cells, the Week all-day row), and both became lessons.
