---
name: new-feature
description: Use when starting any change to Dank Calendar — a new feature, enhancement or behaviour change ("add X", "make the calendar do Y", "I want a setting for Z"), a bug fix ("X is broken") or a chore. Drives the fixed workflow spec → branch → implement → verify → PR → deploy so every change is built the same way.
---

# New feature workflow

Every change follows these phases in order — features (`feat/`), bug fixes (`fix/`) and chores
(`chore/`) alike — except the two trivial changes in `project-manager` step 0 (a
`tasks/lessons.md` edit, a typo in another doc), which skip the issue. Do not skip a phase; if
one does not apply, say so under Size in the issue.

Who does each phase (`project-manager` skill): the PM owns 1, 2 and 7, every `tasks:` commit and
every issue comment. `dcal-builder` (or `dcal-architect` for L, schema or provider work) does 3 on
the branch the PM created in phase 2. `dcal-verifier` does 4. `dcal-reviewer` does 5 when
`project-manager`'s review rule calls for it. In phase 6 `dcal-builder` opens a PR that the owner
merges on GitHub, then pulls and deploys. The merge is the owner's OK: nobody asks for a merge,
push or deploy OK in chat. Phases 3–5 never create or switch branches, and agents never commit
`tasks/` (one exception: phase 6's merge of `origin/master` that resolves a `tasks/lessons.md`
conflict). Writing agents run one at a time in the main checkout, never with
`isolation: worktree`.

## 1. Issue — the spec

1. Read `tasks/lessons.md` (if it exists) for past corrections.
2. Clarify intent with the user until you can state: what the user sees, where it lives in the
   UI, what persists, and what is out of scope. Ask one question at a time; prefer
   multiple choice.
3. `dcal-scout` (briefed by the PM) locates the closest existing feature and reads it
   end-to-end — new code must look like it.
   `dcal-recipes` lists worked examples per feature type. Map it with the code graph first
   (`code-graph` skill): `.claude/tools/graph-calls.py <dir> [--grep name]` gives the
   chain across layers with node ids, then read only the lines it cites. Check
   `graphify-out/memory/` for an earlier trace of the same flow.
4. From the scout's report, decide the layers touched — this goes in the issue's Risks section as
   a tick list:
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
  `#N` would point at the wrong issue there; only the PR body (phase 6) references the issue.
- If something goes sideways (design doesn't fit, unexpected complexity): stop, tell the PM,
  who updates the issue and re-checks with the user.

## 4. Verify

Run the `verify-change` skill. All checks must pass, and the feature must be seen working in a
**dev instance** (`verify-change` section 4) — never `deploy-local`, which installs only
`master` (phase 6, after the owner merged the PR, or `sync-upstream`). A docs-only change
(`verify-change` section 0's docs-only test prints nothing) has no build, dev instance or
service stop: that section covers it. The verifier reports to the PM, and the PM
posts the report as an issue comment (`project-manager`'s format); if `project-manager`'s
review rule doesn't require phase 5, the PM says so in that comment.

## 5. Review

When `project-manager`'s review rule calls for it (every M/L change, and anything touching the
DB, migrations, providers or the background engines
`core/internal/{sync,reminders,invitations}` — this phase is otherwise optional), dispatch
`dcal-reviewer` on `git diff master...HEAD` with the issue number, so it checks the acceptance
criteria and CLAUDE.md's rules. Fix real findings; re-run `verify-change`. The PM posts the
findings and how they were resolved as an issue comment.

## 6. Pull request, merge and deploy

The owner reviews every change as a PR on `valicaa/dankcalendar` and merges it on GitHub (merge
commits only; GitHub then deletes the remote branch). That merge is the OK to deploy — the PM
never asks for a merge, push or deploy OK in chat. `<branch>` below is
`<feat|fix|chore>/<N>-<slug>`. Each block is one Bash call in the main checkout (a subagent's
default cwd); a block that changes it starts with a guard line. A `STOP` is a failed step to
report to the PM.

**6.1 Result (PM).** Commit `tasks/` notes on the feature branch as `tasks: result for <slug>`
(skipped when `git status --short tasks/` prints nothing). Write the PR body to
`<scratchpad>/pr-<N>.md`, linking the evidence comments by the URLs `gh issue comment` printed:

```markdown
Closes #<N>

<what changed, 2–5 lines>

Evidence:
- Verifier: <verdict> — <comment URL>
- Reviewer: <verdict, or "skipped — <why>"> — <comment URL>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

`Closes #<N>` goes on the first line at column 0, and only here — never in a feature commit.
Merging the PR closes the issue, and the fork's merge commit is `<PR title> (#<PR>)` with the PR
body as its message, which is how `upstream-pr` finds it.

**6.2 Push and open the PR (`dcal-builder`).** Push, refusing a branch that conflicts with
`origin/master` (see Conflicts below):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = "<branch>" ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean <branch>"; exit 1; }
git fetch origin
git merge-tree --write-tree --name-only --no-messages origin/master HEAD >/dev/null || { echo "STOP: <branch> conflicts with origin/master"; exit 1; }
git push origin <branch>
```

Then open the PR — `--base` and `--head` always, since a bare `gh pr create` in a fork can
target upstream. The first line refuses a body without `Closes #<N>` first and the attribution
last:

```bash
[ "$(head -1 <scratchpad>/pr-<N>.md)" = "Closes #<N>" ] && tail -1 <scratchpad>/pr-<N>.md | grep -qF 'Generated with [Claude Code]' || { echo "STOP: PR body must start with Closes #<N> and end with the attribution"; exit 1; }
gh pr create -R valicaa/dankcalendar --base master --head <branch> --title "$(gh issue view <N> -R valicaa/dankcalendar --json title -q .title)" --body-file <scratchpad>/pr-<N>.md
```

It prints the PR URL; report it. Then return the main checkout to an up-to-date `master` (the
feature branch stays, for review fixes):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout with a clean tree"; exit 1; }
git switch master || exit 1
git pull --ff-only origin master
```

**6.3 Hand over (PM).** `gh issue comment <N> -R valicaa/dankcalendar --body "PR: <URL>"`, and
give the owner the URL. The feature stays in flight until 6.4 is done or the PR is closed.

**Review requests.** When the owner asks for changes on the PR, phases 3–5 run again on the same
branch. The first brief starts with checking it out again (the pull picks up anything pushed to
it on GitHub, e.g. its "Update branch" button):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git switch <branch> || exit 1
git pull --ff-only origin <branch>
```

Fixes are new commits, never a rewrite. The PM posts the new evidence on the issue and links it
on the PR (`gh pr comment <PR> -R valicaa/dankcalendar --body "<what changed> — <comment URL>"`).
Then `dcal-builder` runs 6.2's push block (the push updates the PR; no second `gh pr create`)
and its return to `master`.

**Conflicts.** When 6.2 stops on a conflict, or the PR shows one
(`gh pr view <PR> -R valicaa/dankcalendar --json mergeable` prints `CONFLICTING`),
`dcal-builder` merges `origin/master` into the feature branch — a merge, not a rebase, so
nothing is force-pushed and no hash cited in an issue comment disappears. On the feature branch
(checked out as above if the checkout is on `master`):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = "<branch>" ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean <branch>"; exit 1; }
git fetch origin
git -c merge.conflictStyle=merge merge origin/master -m "merge: master into <slug>"
```

If it stops on a conflict, resolve it only if `tasks/lessons.md` is the sole conflicted file
(both sides appended rules), by keeping both sides; anything else aborts:

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = "<branch>" ] || { echo "STOP: not the main checkout on <branch>"; exit 1; }
[ "$(git diff --name-only --diff-filter=U)" = tasks/lessons.md ] || { git merge --abort; echo "STOP: conflict beyond tasks/lessons.md"; exit 1; }
sed -i '/^\(<<<<<<< \|=======$\|>>>>>>> \)/d' tasks/lessons.md
! grep -nE '^(<<<<<<<|=======|>>>>>>>|\|{7})' tasks/lessons.md || { git merge --abort; echo "STOP: markers left"; exit 1; }
git add tasks/lessons.md
```

Then, in a separate call, `git commit --no-edit --cleanup=strip` (it keeps the `-m` message).
This merge commit is the one exception to "only the PM commits `tasks/`". The check-docs hook
may block it because the merged-in files trip its doc rules; they were reviewed on `master`
already, so `.claude/tools/check-docs.py --ack` and committing again is expected here. On a
STOP the PM briefs `dcal-builder` (or `dcal-architect`) to resolve the code conflict by hand in
the same merge, and phases 4–5 run again. Either way, finish with 6.2's push block and its
return to `master`.

**6.4 After the merge (`dcal-builder`).** The PM learns of the merge from the owner, or from
`gh pr view <PR> -R valicaa/dankcalendar --json state,mergeCommit` (`"state":"MERGED"`; the
merge commit's `oid` is `<M>`), and briefs this with `<M>`. Pull it and delete the merged local
branch (`-d` refuses a branch whose commits aren't all in `master`; a failed deploy's fix gets
a new branch anyway):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git fetch --prune origin
git pull --ff-only origin master
git merge-base --is-ancestor <M> HEAD || { echo "STOP: <M> is not on master"; exit 1; }
git branch -d <branch>
```

Then `verify-change` section 0's docs-only test, on the merge:

```bash
git diff --name-only <M>~1..<M> | grep -vE '^(\.claude/|tasks/|CLAUDE\.md$|\.graphifyignore$|[^/]+\.md$)'
```

- No output: docs-only, nothing to deploy.
- Any output: run `deploy-local`, then refresh the Go graph
  (`GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`). If
  `git diff --name-only <M>~1..<M> -- '*.qml'` lists files, say so: the QML refresh (`code-graph`
  skill) costs LLM tokens, so the PM offers it to the owner.

Report `<M>`, the branch deletion and the deploy output. `dcal-verifier` then confirms the
deploy landed (installed version, `dcal` service running, a screenshot), and the PM posts the
final comment on the (already closed) issue: `<M>` plus the deploy confirmation, or "docs-only,
nothing deployed".

**If the deploy fails** — `deploy-local` errors, or `dcal-verifier` can't confirm it:

1. `dcal-builder` runs `deploy-local`'s Rollback, reinstalling `<M>~1`. `master` is never reset:
   it moves only by merged PRs.
2. The PM reopens the issue with the evidence: `gh issue reopen <N> -R valicaa/dankcalendar`,
   then `gh issue comment <N> -R valicaa/dankcalendar --body-file <scratchpad>/deploy-failure.md`.
3. The fix goes up as a new PR from a new branch for the same issue, which the PM creates as in
   phase 2, named `fix/<N>-<slug>-2` (`-3` for a third round) whatever the first prefix was:
   `gh issue develop <N> -R valicaa/dankcalendar --name fix/<N>-<slug>-2 --base master --checkout`.
   Phases 3–6 run again on it; its PR body starts with `Closes #<N>` too.

## 7. Offer upstream

If the issue's Constraints says "Upstream-worthy: yes", offer to run `upstream-pr` once the fork
PR is merged. Never open an upstream PR without the user's go-ahead.

## Lessons

When the user corrects your approach, add a dated rule to `tasks/lessons.md` (pattern → rule),
committed with the next `tasks:` commit (no feature branch checked out: `project-manager` step 0).
