# #33 — events: friendly errors and retry for batch actions

Issue: https://github.com/valicaa/dankcalendar/issues/33 — branch `feat/33-friendly-errors-retry-batch-actions`

- [x] Scout: map `EventSelectionModel.mutateEvents` callers (paste, drag-move, delete) and #29's `writeFailure`/`showWriteFailure`/retry contract — dcal-scout
- [x] UI: batch failures use #29's friendly message with a count; Retry resends only failed items; pasted creates send a client uid; raw error to log only; i18n extract — dcal-builder
- [x] Verify: `verify-change` + offline dev instance, scenarios 1–3 — dcal-verifier
- [x] Review: 3 rounds, approve at 9abcff9 — dcal-reviewer
- [x] Result: `tasks: result for friendly-errors-retry-batch-actions`, PR body — PM

## Result
- Verifier pass at 9abcff9 (3 rounds); reviewer approve at 9abcff9 after 2 fix rounds (round-1 blocker: cut-paste could delete an original whose copy failed).
- Known limits in PR body: no reason for all-unclassified batches; Try-while-busy drops the retry; delete-only cut failures don't say the event is now duplicated; note wording.
- Incident: round-1 builder used `hyprctl dispatch` against the dev instance (cursor + special workspace on the live desktop) → lesson added.
