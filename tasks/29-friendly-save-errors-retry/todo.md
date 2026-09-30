# #29 events: friendly save errors with retry

Issue: https://github.com/valicaa/dankcalendar/issues/29 — branch `feat/29-friendly-save-errors-retry`

- [ ] Design: error classes (network / reconnect / generic), IPC error shape (backward-compatible), create-retry without duplicates — dcal-architect
- [ ] Daemon: classify Google provider + IPC write errors (create/update/delete/RSVP), tests — dcal-architect
- [ ] UI: event dialog friendly message + Retry, edits kept; delete/RSVP toast with Retry; raw error to log only; i18n extract — dcal-builder
- [ ] Verify: `verify-change` + dev instance with network blocked (scenarios 1–5) — dcal-verifier
- [ ] Review: diff vs issue #29 + CLAUDE.md (provider touched → required) — dcal-reviewer
- [ ] Result: `tasks: result for friendly-save-errors-retry`, PR body — PM
- [ ] PR: 6.2 push, open PR, checkout back to master — dcal-builder
