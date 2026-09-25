---
name: write-issue
description: Use when writing, editing or triaging any issue on valicaa/dankcalendar — drafting a new feature/bug/chore spec, editing an existing issue body, or triaging one filed through a GitHub issue form (`.github/ISSUE_TEMPLATE/`). The single source for the 8-heading template, title/label rules and slug rules; `project-manager` step 2 and any triage point here instead of holding their own copy.
---

# Write an issue

The issue body is the spec. Every change but `project-manager` step 0's trivial docs edits
(a `tasks/lessons.md` rule or a typo in another doc — see that step for the exact list) starts
as an issue on `valicaa/dankcalendar` built from the template below.

## 0. Check it doesn't already exist

Before drafting, confirm the capability isn't already there:
1. Send `dcal-scout` to check the code and settings for it.
2. `gh issue list -R valicaa/dankcalendar --state all --search "<keywords>"` for an issue that
   already covers it.

If either finds it, tell the user instead of filing. Example: "ISO week numbers in month view"
already exists — `dcal-scout` finds `SettingsData.showWeekNumbers` driving
`quickshell/Modules/views/MonthView.qml:152-238`.

## The template — always 8 headings, in this order

```markdown
## Problem
## Goal / Non-goals
## Story
## Scenarios
## Constraints
## Acceptance
## Risks
## Size
```

Heading lines carry only the heading — guidance goes in the body under each one, never on the
heading line itself, so a copied template doesn't read `## Problem who hits this…`. Issue forms
render each field as an `### ` heading (one level below the `##` a hand-written body uses); both
are the template — never require one level over the other.

- **Problem** — the problem, never the solution, plus today's workaround. A short paragraph, or
  a list for a bug's repro steps (see Variants). A fact you couldn't get from the user: a
  trailing `Unknown: <what>` line — it must never be something Acceptance depends on.
- **Goal / Non-goals** — the appetite (Shape Up) plus an explicit no-gos list.
- **Story** — one INVEST line: `As <user>, I want <capability>, so that <outcome>`.
- **Scenarios** — 1–5, strict Given/When/Then; Then is always the observable, *correct* result
  — never an implementation step, and (bug variant) never the bug itself.
- **Constraints** — standing rules that bind this change (CGO, migrations, I18n, DankCommon)
  plus one line, `Upstream-worthy: yes` or `Upstream-worthy: no`.
- **Acceptance** — a checkable list; every item names the scenario or constraint it proves.
- **Risks** — callers/data/providers/sync touched, plus the layers-touched line (below).
- **Size** — the t-shirt size (below) and which `new-feature` phase doesn't apply, if any.

## Layers-touched tick list

Defined once, used everywhere (Risks, and the forms' Risks field): one line, exactly this
shape, `[x]` for each layer touched (at least one ticked, or the word `none` for pure fork
tooling):

`Layers touched: [ ] QML  [ ] UI setting  [ ] IPC  [ ] DB migration  [ ] provider  [ ] background engine  [ ] HTTP/CLI`

## Variants

- **Feature** (label `enhancement`): the shape above as written.
- **Bug** (label `bug`): Problem holds the repro steps plus expected vs actual result (see
  Facts to collect below). One Scenario is that repro: Given the steps, When run, Then the
  EXPECTED (correct) result — the actual, wrong result stays in Problem, never in a Scenario's
  Then. So "Scenario 1 passes" means the bug is fixed. Goal / Non-goals is usually short ("fix
  it"; no-gos are what NOT to also fix).
- **Chore** (label `chore`): Story may be thin (no end user outcome) — state who benefits (a
  future contributor, CI, the PM) instead of a user-facing capability. The rest is unchanged.

### Facts to collect (bugs)

Ask the user (`project-manager` step 1.3) for: repro steps; expected vs actual result; how
often and since when (a recent version or sync update?); the account/provider involved; error
text or logs (`journalctl --user -u dcal`). Anything still unknown after asking goes on a
trailing `Unknown: <what>` line in Problem — never something an Acceptance item depends on.

## Title, labels, slug

Title: `area: lowercase summary`, no trailing period. `area` is the same open vocabulary as
commit subjects — upstream's most-used areas: `ui`, `i18n`, `core`, `providers`, `events`,
`caldav`, `nix`, `flatpak`, `ci` (see the rest with `git log upstream/master --format=%s | cut
-d: -f1 | sort | uniq -c | sort -rn | head -30`). Fork-only areas: `docs` (CLAUDE.md, skills,
agents) and `tooling` (scripts, hooks). Not `tasks` — upstream uses `tasks:` for its own Tasks
feature; `tasks:` stays only the PM's commit subject for `tasks/` changes, never an issue area.

Labels: exactly one type label (`enhancement`, `bug` or `chore`) and one size label (`size:S`,
`size:M` or `size:L`).

Slug: the title's summary (without `area:`), lowercase kebab-case, 2–5 words (a hyphenated or
slashed word like `free/busy` counts as one). Drop articles, filler, and a generic leading verb
(`add`, `show`, `make`, `support`, `fix`) unless dropping it makes the slug ambiguous:
`events: add free/busy check` → `free-busy-check`; `ui: show week numbers in the month view
header` → `week-numbers-month-header`.

## Size

T-shirt size = the largest of:
- layers touched (the tick list): 1 = S, 2–3 = M, cross-cutting (most layers) = L.
- effort: <1h = S regardless of layers.
- risk: a DB migration or a new provider = L regardless of the rest.

Note which `new-feature` phase doesn't apply and why — name it (e.g. "phase 5 Review — skipped,
single-file docs fix") or point at `new-feature`'s phase list. For a form-filed issue, triage
(below) writes this note into the Size field by editing the body.

## Branch name

Type label picks the prefix: `enhancement` → `feat`, `bug` → `fix`, `chore` → `chore`. Branch
is `<prefix>/<N>-<slug>`. The `gh issue develop` command that cuts it lives in `project-manager`
step 2.

## Creating the issue

Write the body to a temp file (the session scratchpad if you have one), then:

```bash
gh issue create -R valicaa/dankcalendar --title "<area>: <summary>" \
  --body-file <path-to-body.md> --label <enhancement|bug|chore> --label <size:S|size:M|size:L>
```

`N` is the number at the end of the URL this command prints. `project-manager` step 2 shows the
spec to the user and gets a yes before running this — that order, not this skill, is its job.

## Forms

`.github/ISSUE_TEMPLATE/{feature,bug,chore}.yml` render the same 8 fields as textareas (Size is
a dropdown), all `required: true` so none can stay empty. Text that used to be pre-filled with
GitHub's `value:` (the `Upstream-worthy: yes/no` line, the layers line) is now a `placeholder:`
instead — greyed-out example text, not submitted unless the submitter types it — and each
field's `description` says exactly what to write (`Upstream-worthy: yes` or `no`; the layers
line with `[x]`).

## Triage of a form-filed issue

A form-filed issue already carries its type label and an `area: ` title stub. Required fields
can't be empty, but a submitter can still leave a placeholder's example text unedited. Before
`gh issue develop`:

1. Check every field for an untouched placeholder (a literal `Upstream-worthy: yes` or `no`
   copied without a real answer, a layers line with no `[x]`) and the `area: ` title stub.
2. Fix the type label if the wrong form was used (`enhancement`/`bug`/`chore`).
3. Check the picked Size against the ticked layers (Size above); add the matching
   `size:S`/`size:M`/`size:L` label — the form's dropdown doesn't apply one.
4. Fix the title (`area: lowercase summary`) and derive the slug (Slug above) now, before
   cutting the branch.
5. Apply any edit: `gh issue view N -R valicaa/dankcalendar --json body -q .body > <tmpfile>`,
   edit the file, then `gh issue edit N -R valicaa/dankcalendar --body-file <tmpfile>`.
6. A fact only the submitter has (missing repro detail, unclear scope): ask with `gh issue
   comment N -R valicaa/dankcalendar --body-file <tmpfile>` — never guess it.

## Quality checklist

- [ ] existence/duplicate check done (step 0)
- [ ] title is `area: lowercase summary`, no trailing period
- [ ] exactly one type label (`enhancement`/`bug`/`chore`) and one size label (`size:S/M/L`)
- [ ] all 8 headings present, `##` or `###`, in order, nothing merged or dropped
- [ ] Problem states the problem, not a solution ("the settings page has no per-calendar color
      override", not "add a calendar color picker")
- [ ] Goal / Non-goals lists an explicit no-gos
- [ ] Story is one `As <user>, I want <capability>, so that <outcome>` line
- [ ] 1–5 Scenarios, each strict Given/When/Then
- [ ] bug variant: Problem holds repro steps and expected vs actual; one Scenario is the repro
      with Then = the expected (fixed) result
- [ ] Constraints includes `Upstream-worthy: yes` or `Upstream-worthy: no`
- [ ] the layers-touched line is present with at least one `[x]`, or `none` for fork tooling
- [ ] every Acceptance item is checkable and names its scenario or constraint
- [ ] no `Unknown:` item that an Acceptance item depends on

## Worked example (bug)

Title: `caldav: free/busy resets`
Labels: `bug`, `size:S`
Slug: `free-busy-resets`

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
Layers touched: [ ] QML  [ ] UI setting  [ ] IPC  [ ] DB migration  [x] provider  [ ] background engine  [ ] HTTP/CLI
`internal/providers/caldav` write path only.

## Size
S (one layer, <1h).
```
