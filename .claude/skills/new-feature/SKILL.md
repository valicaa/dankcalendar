---
name: new-feature
description: Use when starting any new feature, enhancement, or behaviour change in Dank Calendar — "add X", "make the calendar do Y", "I want a setting for Z". Drives the fixed workflow spec → branch → implement → verify → merge → deploy so every feature is built the same way.
---

# New feature workflow

Every feature follows these phases in order. Do not skip a phase; if one does not apply,
say so under Size in the issue.

Who does each phase (`project-manager` skill): the PM owns 1, 2 and 7, and getting the user's
one OK (merge + deploy + graph refresh) before 6. `dcal-builder` (or `dcal-architect` for L,
schema or provider work) does 3 on the branch the PM already created in phase 2, and — once
that OK is given — the merge/deploy/graph-refresh in 6. `dcal-verifier` does 4 and confirms the
deploy in 6. `dcal-reviewer` does 5 when `project-manager`'s review rule calls for it.

## 1. Issue — the spec

1. Read `tasks/lessons.md` (if it exists) for past corrections.
2. Clarify intent with the user until you can state: what the user sees, where it lives in the
   UI, what persists, and what is out of scope. Ask one question at a time; prefer
   multiple choice.
3. Locate the closest existing feature and read it end-to-end — new code must look like it.
   `dcal-recipes` lists worked examples per feature type. Map it with the code graph first
   (`code-graph` skill): `.claude/tools/graph-calls.py <dir> [--grep name]` gives the
   chain across layers with node ids, then read only the lines it cites. Check
   `graphify-out/memory/` for an earlier trace of the same flow.
4. Decide the layers touched — this goes in the issue's Risks section as a tick list:
   - [ ] QML only (view/widget/modal)
   - [ ] UI setting (`SettingsData`) — daemon reads it too?
   - [ ] New IPC method(s)
   - [ ] DB schema change / migration (**one-way door — needs explicit user approval**)
   - [ ] Provider behaviour (google/caldav/microsoft/evolution/local/ical)
   - [ ] HTTP API / CLI subcommand

   For each existing function you will change, list its callers in the same Risks section.
   Use the `<-` and `~ call sites` lines from `graph-calls.py`, plus
   `graphify affected <node-id> --relation calls --depth 3` for transitive callers. Grep for
   interface implementations and callbacks, which the graph can't see.
5. Write the issue body using `project-manager`'s template (Problem, Goal/Non-goals, Story,
   Scenarios, Constraints, Acceptance, Risks, Size — always these 8 headings; "Upstream-worthy:
   yes/no" is a line under Constraints, not its own heading). **Show it to the user and get
   their yes before creating the issue** — order matters, see `project-manager` step 2.

## 2. Branch

The PM creates the issue, the branch and `tasks/<N>-<slug>/todo.md` in this phase — see
`project-manager` step 2 for the exact commands (freshness check via `git fetch origin` +
`git rev-list --count origin/master..master`, never `git switch master`; `gh issue develop`;
the `todo.md` work breakdown and its `tasks: plan for <slug>` commit). A builder or architect
never creates or switches a branch — it always starts phase 3 on the branch the PM handed it.

## 3. Implement

- Follow `dcal-recipes` for each layer. Backend first (method + test), then QML.
- Go changes get tests in the same commit (TDD where practical: failing test first).
- Every new user-facing string: `I18n.tr("…", "context")`, then `make i18n-extract` and commit
  the `translations/en.json` diff with the change that introduced the strings.
- Commit in small, self-contained steps: `area: lowercase summary`. No `tasks/` files mixed
  into code commits, and no `#N` or `Closes #N` in feature commits — cherry-picked upstream,
  `#N` would point at the wrong issue there; only the merge commit references the issue.
- If something goes sideways (design doesn't fit, unexpected complexity): stop, tell the PM,
  who updates the issue and re-checks with the user.

## 4. Verify

Run the `verify-change` skill. All checks must pass, and the feature must be seen working in a
**dev instance** (`verify-change`'s hot-reload / `make run` steps: stop the service, prove it,
restart the service) — never `deploy-local`, which is phase 6 only, after the user's merge OK
and only on `master`. Post the verifier report as an issue comment (`project-manager`'s
format); if `project-manager`'s review rule doesn't require phase 5, say so in that comment.

## 5. Review

When `project-manager`'s review rule calls for it (every M/L change, and anything touching the
DB, migrations, providers or sync — this phase is otherwise optional), dispatch `dcal-reviewer`
on `git diff master...HEAD` with the issue number, so it checks the acceptance criteria and
CLAUDE.md's rules. Fix real findings; re-run `verify-change`. Post the findings and how they
were resolved as an issue comment.

## 6. Merge and deploy

The PM gets the user's one explicit OK — merge, deploy, and the graph refresh together — and
does not run any of this itself. Once granted, brief `dcal-builder`:

1. Commit any `tasks/<N>-<slug>/` follow-up notes as `tasks: result for <slug>` **on the
   feature branch, before merging**, so `master` matches `origin/master` right after the push:

   ```bash
   git switch <feat|fix|chore>/<N>-<slug>
   git add tasks/<N>-<slug> && git commit -m "tasks: result for <slug>"
   git switch master && git merge --no-ff <feat|fix|chore>/<N>-<slug> -m "merge: <slug>

   Closes #<N>"
   git push origin master <feat|fix|chore>/<N>-<slug>
   ```

   `Closes #N` belongs only in this merge commit message — never in a feature commit — so
   pushing `master` closes the issue.
2. Run `deploy-local`.
3. If any `.qml` file changed in the diff (`git diff --name-only master~1..master -- '*.qml'`),
   refresh the graph: `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify
   update .`, plus the QML refresh from the `code-graph` skill if
   `.claude/tools/graph-qml.py status` lists many files — this is the LLM-costing step the PM's
   one question already covered.

Then send `dcal-verifier` to confirm the deploy actually landed (installed version, `dcal`
service running, a screenshot) and post the final issue comment (merge hash + deploy
confirmation, per `project-manager` step 5).

## 7. Offer upstream

If the issue's Constraints says "Upstream-worthy: yes", offer to run `upstream-pr`. Never open
a PR without the user's go-ahead.

## Lessons

When the user corrects your approach at any point, add a dated rule to `tasks/lessons.md`
(pattern → rule) and commit it with the next `tasks:` commit.
