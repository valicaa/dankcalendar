---
name: new-feature
description: Use when starting any new feature, enhancement, or behaviour change in Dank Calendar — "add X", "make the calendar do Y", "I want a setting for Z". Drives the fixed workflow spec → branch → implement → verify → merge → deploy so every feature is built the same way.
---

# New feature workflow

Every feature follows these phases in order. Do not skip a phase; if one does not apply,
say so explicitly in the spec.

## 1. Understand and spec

1. Read `tasks/lessons.md` (if it exists) for past corrections.
2. Clarify intent with the user until you can state: what the user sees, where it lives in the
   UI, what persists, and what is out of scope. Ask one question at a time; prefer
   multiple choice.
3. Locate the closest existing feature and read it end-to-end — new code must look like it.
   `dcal-recipes` lists worked examples per feature type.
4. Decide the layers touched (tick in the spec):
   - [ ] QML only (view/widget/modal)
   - [ ] UI setting (`SettingsData`) — daemon reads it too?
   - [ ] New IPC method(s)
   - [ ] DB schema change / migration (**one-way door — needs explicit user approval**)
   - [ ] Provider behaviour (google/caldav/microsoft/local/ical)
   - [ ] HTTP API / CLI subcommand
5. Write `tasks/<slug>/spec.md` with: goal, UX description, layers, files to touch, test plan,
   risks, upstream-PR fitness (would AvengeMedia plausibly want this?). Keep it short.
6. Write `tasks/<slug>/todo.md` as checkable steps. **Show the spec to the user and wait for
   approval before writing code.**

## 2. Branch

```bash
git switch master && git pull --ff-only origin master
git switch -c feat/<slug>
git add tasks/<slug> && git commit -m "tasks: spec for <slug>"
```

Planning docs stay in their own commits (the `upstream-pr` skill drops them).

## 3. Implement

- Follow `dcal-recipes` for each layer. Backend first (method + test), then QML.
- Go changes get tests in the same commit (TDD where practical: failing test first).
- Every new user-facing string: `I18n.tr("…", "context")`, then `make i18n-extract` and commit
  the `translations/en.json` diff with the change that introduced the strings.
- Commit in small, self-contained steps: `area: lowercase summary`. No `tasks/` files mixed
  into code commits. Tick items in `todo.md` as you go (commit those separately or at the end).
- If something goes sideways (design doesn't fit, unexpected complexity): stop, update the
  spec, and re-check with the user.

## 4. Verify

Run the `verify-change` skill. All checks must pass, and the feature must be seen working
in the running app (screenshot) — not just compiled.

## 5. Review

Dispatch a reviewer subagent (e.g. `brutal-code-reviewer`) on `git diff master...HEAD`
with CLAUDE.md's rules as the checklist. Fix real findings; re-run `verify-change`.

## 6. Merge and deploy

After the user confirms they're happy:

```bash
git switch master && git merge --no-ff feat/<slug> -m "merge: <slug>"
git push origin master feat/<slug>
```

Then run `deploy-local`. Append a `## Result` section to `tasks/<slug>/spec.md` (what shipped,
deviations from spec, follow-ups) and commit it as `tasks: result for <slug>`.

## 7. Offer upstream

If the spec marked it upstream-worthy, offer to run `upstream-pr`. Never open a PR without
the user's go-ahead.

## Lessons

When the user corrects your approach at any point, add a dated rule to `tasks/lessons.md`
(pattern → rule) and commit it with the next `tasks:` commit.
