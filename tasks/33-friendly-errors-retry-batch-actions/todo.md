# #33 — events: friendly errors and retry for batch actions

Issue: https://github.com/valicaa/dankcalendar/issues/33 — branch `feat/33-friendly-errors-retry-batch-actions`

- [ ] Scout: map `EventSelectionModel.mutateEvents` callers (paste, drag-move, delete) and #29's `writeFailure`/`showWriteFailure`/retry contract — dcal-scout
- [ ] UI: batch failures use #29's friendly message with a count; Retry resends only failed items; pasted creates send a client uid; raw error to log only; i18n extract — dcal-builder
- [ ] Verify: `verify-change` + offline dev instance, scenarios 1–3 — dcal-verifier
- [ ] Review: optional (S, QML only) — dcal-reviewer
- [ ] Result: `tasks: result for friendly-errors-retry-batch-actions`, PR body — PM
