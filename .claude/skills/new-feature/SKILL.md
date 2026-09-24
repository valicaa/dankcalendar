---
name: new-feature
description: Use when starting any change to Dank Calendar — a new feature, enhancement or behaviour change ("add X", "make the calendar do Y", "I want a setting for Z"), a bug fix ("X is broken") or a chore. Drives the fixed workflow spec → branch → implement → verify → merge → deploy so every change is built the same way.
---

# New feature workflow

Every change follows these phases in order — features (`feat/`), bug fixes (`fix/`) and chores
(`chore/`) alike. Do not skip a phase; if one does not apply, say so under Size in the issue.

Who does each phase (`project-manager` skill): the PM owns 1, 2 and 7, every `tasks:` commit,
and getting the user's one OK (merge + deploy + graph refresh) before 6. `dcal-builder` (or
`dcal-architect` for L, schema or provider work) does 3 on the branch the PM created in phase 2.
`dcal-verifier` does 4. `dcal-reviewer` does 5 when `project-manager`'s review rule calls for
it. In phase 6 `dcal-builder` merges, deploys and refreshes the graph, `dcal-verifier` confirms
the deploy, then `dcal-builder` pushes. Phases 3–5 never create or switch branches, and agents
never commit `tasks/`. Writing agents run one at a time in the main checkout, never with
`isolation: worktree`.

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
   - [ ] Background engine (`core/internal/{sync,reminders,invitations}`)
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
`project-manager` step 2 for the exact commands (main checkout on `master` with a clean tree,
one feature in flight; freshness check via `git fetch origin` +
`git rev-list --count origin/master..master`; `gh issue develop … --checkout`; the `todo.md`
work breakdown and its `tasks: plan for <slug>` commit). Phase 3 starts on that branch.

## 3. Implement

- Follow `dcal-recipes` for each layer. Backend first (method + test), then QML.
- Go changes get tests in the same commit (TDD where practical: failing test first).
- Every new user-facing string: `I18n.tr("…", "context")`, then `make i18n-extract` and commit
  the `translations/en.json` diff with the change that introduced the strings.
- Commit in small, self-contained steps: `area: lowercase summary`. Never commit `tasks/`
  (the PM does), and no `#N` or `Closes #N` in feature commits — cherry-picked upstream,
  `#N` would point at the wrong issue there; only the merge commit references the issue.
- If something goes sideways (design doesn't fit, unexpected complexity): stop, tell the PM,
  who updates the issue and re-checks with the user.

## 4. Verify

Run the `verify-change` skill. All checks must pass, and the feature must be seen working in a
**dev instance** (`verify-change` section 4) — never `deploy-local`, which installs only
`master` (phase 6, after the user's merge OK, or after `sync-upstream`). Post the verifier
report as an issue comment (`project-manager`'s format); if `project-manager`'s review rule
doesn't require phase 5, say so in that comment.

## 5. Review

When `project-manager`'s review rule calls for it (every M/L change, and anything touching the
DB, migrations, providers or the background engines
`core/internal/{sync,reminders,invitations}` — this phase is otherwise optional), dispatch
`dcal-reviewer` on `git diff master...HEAD` with the issue number, so it checks the acceptance
criteria and CLAUDE.md's rules. Fix real findings; re-run `verify-change`. Post the findings
and how they were resolved as an issue comment.

## 6. Merge and deploy

The PM gets the user's one explicit OK — merge, deploy, and the graph refresh together. The PM
then commits any `tasks/` notes on the feature branch as `tasks: result for <slug>` (skipped
when `git status --short tasks/` prints nothing) and briefs `dcal-builder`, which runs, in the
main checkout:

1. Merge onto an up-to-date `master`:

   ```bash
   git status --short                      # must print nothing
   git switch master
   git pull --ff-only origin master
   git merge --no-ff <feat|fix|chore>/<N>-<slug> -m "merge: <slug>" -m "Closes #<N>"
   ```

   The second `-m` puts `Closes #<N>` on its own line at column 0. It belongs only in this
   merge commit message — never in a feature commit — so pushing `master` closes the issue.
   If the merge stops on a conflict in `tasks/lessons.md` alone (both sides appended rules),
   keep both sides; the commit keeps the `-m` message:

   ```bash
   sed -i '/^\(<<<<<<< \|=======$\|>>>>>>> \)/d' tasks/lessons.md
   git add tasks/lessons.md && git commit --no-edit --cleanup=strip
   ```

   Any other conflict: `git merge --abort`, and report it to the PM.
2. Run `deploy-local`.
3. If any `.qml` file changed in the merge (`git diff --name-only master~1..master -- '*.qml'`),
   refresh the graph: `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify
   update .`, plus the QML refresh from the `code-graph` skill if
   `.claude/tools/graph-qml.py status` lists many files — this is the LLM-costing step the PM's
   one question already covered.

Then `dcal-verifier` confirms the deploy actually landed (installed version, `dcal` service
running, a screenshot). Only then does `dcal-builder` push — this closes the issue:

```bash
git push origin master <feat|fix|chore>/<N>-<slug>
```

If the deploy fails, don't push: the issue stays open, `deploy-local`'s Rollback restores the
calendar, and the PM takes the failure to the user. After the push the PM posts the final issue
comment (merge hash + deploy confirmation, per `project-manager` step 5).

## 7. Offer upstream

If the issue's Constraints says "Upstream-worthy: yes", offer to run `upstream-pr`. Never open
a PR without the user's go-ahead.

## Lessons

When the user corrects your approach at any point, add a dated rule to `tasks/lessons.md`
(pattern → rule) and commit it with the next `tasks:` commit.
