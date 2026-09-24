---
name: new-feature
description: Use when starting any new feature, enhancement, or behaviour change in Dank Calendar — "add X", "make the calendar do Y", "I want a setting for Z". Drives the fixed workflow spec → branch → implement → verify → merge → deploy so every feature is built the same way.
---

# New feature workflow

Every feature follows these phases in order. Do not skip a phase; if one does not apply,
say so explicitly in the spec.

Who does each phase (`project-manager` skill): the PM owns 1 (code lookups in steps 3–4 go
to `dcal-scout`), getting the user's merge-and-deploy OK before 6, and 7. The PM does no
execution in 6 itself. `dcal-builder` (or `dcal-architect` for L, schema or provider work)
does 2–3 and, once the PM has that OK, the merge/deploy/graph-refresh steps in 6;
`dcal-verifier` does 4 and confirms the deploy in 6; `dcal-reviewer` does 5.

## 1. Understand and spec

1. Read `tasks/lessons.md` (if it exists) for past corrections.
2. Clarify intent with the user until you can state: what the user sees, where it lives in the
   UI, what persists, and what is out of scope. Ask one question at a time; prefer
   multiple choice.
3. Locate the closest existing feature and read it end-to-end — new code must look like it.
   `dcal-recipes` lists worked examples per feature type. Map it with the code graph first
   (`code-graph` skill): `.claude/tools/graph-calls.py <dir> [--grep name]` gives the
   chain across layers with node ids, then read only the lines it cites. Check
   `graphify-out/memory/` for an earlier trace of the same flow.
4. Decide the layers touched (tick in the spec):
   - [ ] QML only (view/widget/modal)
   - [ ] UI setting (`SettingsData`) — daemon reads it too?
   - [ ] New IPC method(s)
   - [ ] DB schema change / migration (**one-way door — needs explicit user approval**)
   - [ ] Provider behaviour (google/caldav/microsoft/evolution/local/ical)
   - [ ] HTTP API / CLI subcommand

   For each existing function you will change, list its callers and put them in the spec's
   files/risks. Use the `<-` and `~ call sites` lines from `graph-calls.py`, plus
   `graphify affected <node-id> --relation calls --depth 3` for transitive callers. Grep for
   interface implementations and callbacks, which the graph can't see.
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

Dispatch `dcal-reviewer` on `git diff master...HEAD` with the spec path, so it checks the
acceptance criteria and CLAUDE.md's rules. Fix real findings; re-run `verify-change`.

## 6. Merge and deploy

The PM gets the user's explicit OK to merge and deploy; it does not run any of this itself.
Once granted, brief `dcal-builder` to:

```bash
git switch master && git merge --no-ff feat/<slug> -m "merge: <slug>"
git push origin master feat/<slug>
```

then run `deploy-local`, refresh the graph (`GRAPHIFY_VIZ_NODE_LIMIT=0
~/.local/share/graphify-venv/bin/graphify update .`, plus the QML refresh if
`.claude/tools/graph-qml.py status` lists many files), append a `## Result` section to
`tasks/<slug>/spec.md` (what shipped, deviations from spec, follow-ups) and commit it as
`tasks: result for <slug>`. Then send `dcal-verifier` to confirm the deploy actually landed:
the installed version, the `dcal` service is running, and a screenshot of it working.

## 7. Offer upstream

If the spec marked it upstream-worthy, offer to run `upstream-pr`. Never open a PR without
the user's go-ahead.

## Lessons

When the user corrects your approach at any point, add a dated rule to `tasks/lessons.md`
(pattern → rule) and commit it with the next `tasks:` commit.
