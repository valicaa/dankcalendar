---
name: write-issue
description: Use when writing, editing or triaging any issue on valicaa/dankcalendar — drafting a new feature/bug/chore spec, editing an existing issue body, or triaging one filed through a GitHub issue form (`.github/ISSUE_TEMPLATE/`). The single source for the 8-heading template, title/label rules and slug rules; `project-manager` step 2 and any triage point here instead of holding their own copy.
---

# Write an issue

The issue body is the spec. Every change but `project-manager` step 0's trivial docs edits
starts as an issue on `valicaa/dankcalendar` built from the template below.

## The template — always 8 headings

```markdown
## Problem        who hits this, when, today's workaround (one paragraph)
## Goal / Non-goals   Shape Up appetite: the size we are willing to spend; no-gos listed
## Story          As <user>, I want <capability>, so that <outcome>   (INVEST)
## Scenarios      Given <state> / When <action> / Then <observable result>   (1–5)
## Constraints    CGO_ENABLED=0; migration needs explicit approval + backup; I18n.tr for
                  strings; quickshell/DankCommon read-only; Upstream-worthy: yes/no
## Acceptance     checkable list, each tied to a scenario or constraint
## Risks          callers touched, data, providers, sync; layers touched (tick list: QML,
                  UI setting, IPC, DB migration, provider, background engine, HTTP/CLI)
## Size           t-shirt: S (one layer, <1h) | M (2–3 layers) | L (cross-cutting, schema,
                  new provider); any new-feature phase that doesn't apply, and why
```

Always these 8 headings, in this order, nothing merged or dropped:
- **Problem** — the problem, never the solution; one paragraph.
- **Goal / Non-goals** — the appetite (Shape Up) plus an explicit no-gos list.
- **Story** — one INVEST line, `As <user>, I want <capability>, so that <outcome>`.
- **Scenarios** — 1–5, each strict Given/When/Then with an observable Then, not an
  implementation step.
- **Constraints** — the standing rules that bind this change (CGO, migrations, I18n,
  DankCommon) plus `Upstream-worthy: yes/no` as a line here, never its own heading.
- **Acceptance** — a checkable list; every item names the scenario or constraint it proves.
- **Risks** — callers/data/providers/sync touched, and the layers-touched tick list (QML, UI
  setting, IPC, DB migration, provider, background engine, HTTP/CLI) as a line here, never its
  own heading.
- **Size** — the t-shirt size, and which `new-feature` phase doesn't apply and why, if any.

Issue forms render each field as an `### ` heading (one level below the `##` a hand-written
body uses); both are the template — never require one level over the other.

## Variants

- **Feature** (label `enhancement`): the shape above as written.
- **Bug** (label `bug`): Problem holds the repro steps plus expected vs actual result, not just
  a symptom; one Scenario is that repro, Given the steps, When run, Then the actual (wrong)
  result. Goal / Non-goals is usually short ("fix it", no-gos are what NOT to also fix).
- **Chore** (label `chore`): Story may be thin (no end user outcome) — state who benefits
  (a future contributor, CI, the PM) instead of a user-facing capability; the rest is unchanged.

## Title, labels, slug

Title: `area: lowercase summary`. `area` comes from upstream's vocabulary — `ui`, `i18n`,
`core`, `events`, `providers`, `caldav`, `settings`, `sync`, `reminders`, `notifications`,
`keyring`, `ipc`, `nix`, `flatpak`, `ci` — or, for fork-only work, `docs` (CLAUDE.md, skills,
agents), `tooling` (scripts, hooks) or `tasks` (only `tasks/` changes).

Labels: exactly one type label (`enhancement`, `bug` or `chore`) and one size label
(`size:S`, `size:M` or `size:L`).

Slug: the title's summary (without `area:`), lowercase kebab-case, 2–5 words (a hyphenated or
slashed word like `free/busy` counts as one). Drop articles and filler, keep the most specific
words: `events: add free/busy check` → `add-free-busy-check`; `ui: show week numbers in the
month view header` → `week-numbers-month-header`.

## Creating the issue

```bash
gh issue create -R valicaa/dankcalendar --title "<area>: <summary>" --body-file \
  <scratchpad>/issue-body.md --label <enhancement|bug|chore> --label <size:S|size:M|size:L>
```

`N` is the number at the end of the URL this command prints. `project-manager` step 2 shows the
spec to the user and gets a yes before running this — that order, not this skill, is its job.

## Triage of a form-filed issue

An issue opened through `.github/ISSUE_TEMPLATE/feature.yml`, `bug.yml` or `chore.yml` already
carries its type label and a title pre-filled with `area: `. Triage:
1. Add the size label — the form's Size field is a dropdown (S/M/L) but applies no label; add
   `size:S|size:M|size:L` to match what was picked.
2. Run the quality checklist below; a heading GitHub left empty (the submitter skipped an
   optional-looking field) gets asked for or filled in from the thread before work starts.
3. Confirm the title still matches the vocabulary and the slug rules once the branch is cut.

## Quality checklist

- [ ] all 8 headings present, `##` or `###`, in order
- [ ] Constraints includes the `Upstream-worthy: yes/no` line
- [ ] Risks includes the layers-touched tick list
- [ ] every Acceptance item is checkable and names the scenario or constraint it proves
- [ ] Problem states the problem, not a solution ("the month view can't show week numbers", not
      "add a `showWeekNumbers` setting")

## Worked example (bug)

```markdown
## Problem
Free/busy status is missing on events created via CalDAV since the 2026-09 sync update; the
user has to reopen the event and set it manually every time. Repro: create an event on a CalDAV
calendar → save → reopen it. Expected: free/busy matches the create dialog's setting. Actual:
free/busy always reads "Busy" regardless of what was picked.

## Goal / Non-goals
Fix the CalDAV write path. Non-goal: other providers (only CalDAV regressed).

## Story
As a CalDAV user, I want the free/busy I pick at create time to stick, so that my calendar
stays accurate without a second edit.

## Scenarios
1. Given a CalDAV calendar, When I create an event with free/busy "Free", Then reopening it
   shows "Free".

## Constraints
CGO_ENABLED=0; no migration; Upstream-worthy: yes.

## Acceptance
- [ ] Scenario 1 passes against a live CalDAV test calendar

## Risks
Layers touched: provider (caldav). `internal/providers/caldav` write path only.

## Size
S (one layer, <1h).
```
