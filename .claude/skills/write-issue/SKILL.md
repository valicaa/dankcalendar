---
name: write-issue
description: Use when writing, editing or triaging any issue on valicaa/dankcalendar — drafting a new feature/bug/chore spec, editing an existing issue body, or triaging one filed through a GitHub issue form (`.github/ISSUE_TEMPLATE/`). The single source for the 8-heading template, title/label rules and slug rules; `project-manager` step 2 and any triage point here instead of holding their own copy.
---

# Write an issue

The issue body is the spec. Every change but `project-manager` step 0's trivial docs edits
starts as an issue on `valicaa/dankcalendar` built from the template below.

## 0. Check it doesn't already exist

Before drafting, confirm the change is needed:
1. Feature or chore: send `dcal-scout` to check whether the capability already exists in code
   or settings.
2. Bug: check whether it's already fixed — `git fetch upstream && git log master
   upstream/master --oneline -i --grep "<keyword>"`, plus closed issues on both repos. If the
   fix is only on `upstream/master`, offer `sync-upstream` instead of filing. The underlying
   capability existing is expected for a bug report; it isn't a reason to stop.
3. All types: search both repos for a duplicate issue — `gh issue list -R valicaa/dankcalendar
   --state all --search "<keywords>"` and `gh issue list -R AvengeMedia/dankcalendar --state all
   --search "<keywords>"`. Ignore the fork's closed issues titled `TEST …` (any TEST-prefixed
   title, e.g. `TEST (walkthrough…)` or `TEST (form check): …`).

If it fully exists or is already fixed, tell the user instead of filing. Example: "ISO week
numbers in month view" already exists — `dcal-scout` finds `SettingsData.showWeekNumbers`
driving `quickshell/Modules/views/MonthView.qml:152-238`. If only part is missing, file a
narrower issue for the missing part alone, and say in Problem what already exists (file:line).

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
render each field as an `### ` heading, one level below the `##` a hand-written body uses (see
the Quality checklist's `##`/`###` rule).

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

Used in Risks and the forms' Risks field: one line, exactly this shape, `[x]` for each layer
touched (at least one ticked), or for pure fork tooling the whole line replaced with exactly
`Layers touched: none`:

`Layers touched: [ ] QML  [ ] UI setting  [ ] IPC  [ ] DB migration  [ ] provider  [ ] background engine  [ ] HTTP/CLI`

## Variants

- **Feature** (label `enhancement`): the shape above as written.
- **Bug** (label `bug`): Problem holds the repro steps plus expected vs actual result (see
  Facts to collect below). One Scenario is that repro, following the Scenarios rule above; so
  "Scenario 1 passes" means the bug is fixed. Goal / Non-goals is usually short ("fix it";
  no-gos are what NOT to also fix).
- **Chore** (label `chore`): Story may be thin (no end user outcome) — state who benefits (a
  future contributor, CI, the PM) instead of a user-facing capability. The rest is unchanged.

### Facts to collect (bugs)

`project-manager` step 1.3 lists what to ask the user for a bug report — read it before
drafting. Anything still unknown after asking follows the `Unknown:` rule above (Problem).

## Title, labels, slug

Title: `area: lowercase summary`, no trailing period. `area` is spelled the way upstream spells
it, in lowercase (`caldav:`, not `CalDAV:`); the title-case rule applies to the summary, where
proper nouns and acronyms keep their case as upstream does: `Google`, `CalDAV`, `ICS`, `DST`.
`area` is the same open vocabulary as commit subjects — use the most specific area upstream uses
(e.g. `providers/google` is fine) — upstream's most-used areas: `ui`, `i18n`, `core`,
`providers`, `events`, `caldav`, `nix`, `flatpak`, `ci` (see the rest with `git log
upstream/master --format=%s | cut -d: -f1 | sort | uniq -c | sort -rn | head -30`). Fork-only
areas: `docs` (CLAUDE.md, skills, agents) and `tooling` (scripts, hooks). `tasks` means
upstream's Tasks feature; never use it as an issue area for the fork's `tasks/` directory
(`tasks:` stays the PM's commit subject for `tasks/` commits).

Labels: exactly one type label (`enhancement`, `bug` or `chore`) and one size label (`size:S`,
`size:M` or `size:L`).

Slug: the title's summary (without `area:`), lowercase kebab-case, 2–5 words (a hyphenated or
slashed word like `free/busy` counts as one). Drop these fillers when dropping them doesn't make
the slug ambiguous: articles, prepositions, and the generic verbs `add`, `show`, `make`,
`support`, `fix`, `allow`, `enable`, `implement`. Other verbs (`index`, `export`, …) stay:
`events: add free/busy check` → `free-busy-check`; `ui: show week numbers in the month view
header` → `week-numbers-month-view-header`. If still over 5 words, keep the 5 most specific.

## Size

T-shirt size:
- Base it on layers touched (the tick list): 1 layer ticked = S, 2–3 = M, 4 or more, or
  cross-cutting (touches most layers), = L.
- Raise to L for any DB migration or a new provider, regardless of the base.
- Lower to S when the whole change is under 1h, adds no migration and no new provider,
  regardless of the base.
- Fork tooling (`Layers touched: none`) is sized by effort instead: <1h = S, up to 1 day = M,
  more = L.
- A bug whose root cause is still unknown gets a provisional size, marked `(provisional)` —
  re-size once the cause is known.
- A shared core package with no layer of its own (e.g. `internal/recurrence`, `icalconv`)
  counts under the layer(s) of its callers; note that in Risks.
- Review follows `project-manager`'s review rule, regardless of size.

Note which `new-feature` phase is skipped and why (see Skippable phases below), or say none is
skipped. For a form-filed issue, triage (below) writes this size and note into the `### Size`
field by editing the body.

## Skippable phases

- Phase 6.4 deploy: skipped for a docs-only change (the `new-feature` 6.4 docs-only test prints
  nothing).
- Phase 7 upstream offer: skipped when `Upstream-worthy: no`.
- Phase 5 review: review follows `project-manager`'s review rule, regardless of size. Check
  `new-feature`'s phase list for any other phase.

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

`N` is the number at the end of the URL this command prints (after the user's yes —
`project-manager` step 2).

## Forms

`.github/ISSUE_TEMPLATE/{feature,bug,chore}.yml` render the same 8 fields as textareas (Size is
a dropdown), all `required: true` so none can stay empty. A field's `placeholder:` is example
text shown only until the submitter types something — it is never submitted, so an empty
required field is rejected by GitHub, not filed as a blank section. Each field's `description`
says exactly what to write (`Upstream-worthy: yes` or `no`; the layers line with `[x]`).

## Triage of a form-filed issue

A form-filed issue already carries its type label and an `area: ` title stub. Required fields
can't be empty, but they can still be wrong. Before `gh issue develop`, run step 0 and the
Quality checklist (below) on the submitted body, and again after your edits; fix what you can,
and ask the submitter about the rest. In particular check for the title still reading the
`area: ` stub, or outside the title rule (Title above).

Fix what triage finds:
1. Title: `gh issue edit N -R valicaa/dankcalendar --title "area: lowercase summary"`.
2. Wrong form used: `gh issue edit N -R valicaa/dankcalendar --remove-label enhancement
   --add-label bug` (swap `--remove-label`/`--add-label` to whichever type label is wrong).
3. Size: pick it against the ticked layers (Size above), rewrite the body's `### Size` section
   to the triaged size plus its skipped-phase note, then label it: `gh issue edit N -R
   valicaa/dankcalendar --add-label size:M`.
4. Any body edit: `gh issue view N -R valicaa/dankcalendar --json body -q .body > <tmpfile>`,
   edit the file, then `gh issue edit N -R valicaa/dankcalendar --body-file <tmpfile>`.
5. A fact only the submitter has (missing repro detail, unclear scope): ask with `gh issue
   comment N -R valicaa/dankcalendar --body-file <tmpfile>` — never guess it.

An issue the owner filed through a form is Ready after triage; the PM asks the owner again only
if triage changed its scope, not for a title/label/size fix. Don't cut the branch (`gh issue
develop`) while a question to the submitter is still open.

## Quality checklist

- [ ] existence/duplicate check done (step 0)
- [ ] title is `area: lowercase summary` (proper nouns/acronyms keep their case), no trailing
      period
- [ ] exactly one type label (`enhancement`/`bug`/`chore`) and one size label (`size:S/M/L`)
- [ ] all 8 headings present, `##` or `###`, in order, nothing merged or dropped
- [ ] Problem states the problem, not a solution ("the settings page has no per-calendar color
      override", not "add a calendar color picker")
- [ ] Goal / Non-goals states an appetite and explicit no-gos
- [ ] Story is one `As <user>, I want <capability>, so that <outcome>` line
- [ ] 1–5 Scenarios, each strict Given/When/Then
- [ ] bug variant: Problem holds repro steps and expected vs actual; one Scenario is the repro
      with Then = the expected (fixed) result
- [ ] Constraints includes `Upstream-worthy: yes` or `Upstream-worthy: no` on its own line
- [ ] the layers-touched line is present with at least one `[x]`, or is exactly `Layers touched:
      none` for fork tooling
- [ ] every Acceptance item is checkable and names its scenario or constraint
- [ ] no `Unknown:` item that an Acceptance item depends on
- [ ] Size matches the rule (Size above) and states the skipped-phase note (or that none apply)

## Worked example (bug)

Title: `caldav: free/busy resets`
Labels: `bug`, `size:S`
Slug: `free-busy-resets`

```markdown
## Problem
Free/busy on events created via CalDAV always reads "Busy" since the 2026-09 sync update,
regardless of what was picked at create time; the user has to reopen the event and set it
manually every time. Repro: create an event on a CalDAV calendar → save → reopen it. Expected:
free/busy matches the create dialog's setting. Actual: it always reads "Busy".

## Goal / Non-goals
Fix the CalDAV write path. Appetite: S. Non-goal: other providers (only CalDAV regressed).

## Story
As a CalDAV user, I want the free/busy I pick at create time to stick, so that my calendar
stays accurate without a second edit.

## Scenarios
1. Given a CalDAV calendar, When I create an event with free/busy "Free", Then reopening it
   shows "Free".

## Constraints
CGO_ENABLED=0; no migration.
Upstream-worthy: yes

## Acceptance
- [ ] Scenario 1 passes against a live CalDAV test calendar

## Risks
Layers touched: [ ] QML  [ ] UI setting  [ ] IPC  [ ] DB migration  [x] provider  [ ] background engine  [ ] HTTP/CLI
`internal/providers/caldav` write path only.

## Size
S (provisional) — one layer touched, <1h estimated, no migration, but the root cause in the
CalDAV write path isn't confirmed yet, so it follows the provisional-size rule. No phase
skipped — phase 5 review is required despite the S size because Risks ticks provider.
```
