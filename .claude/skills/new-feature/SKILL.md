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
merges on GitHub, then pulls and deploys; it also switches to the branch and back for a review
round. The merge is the owner's OK: nobody asks for a merge, push or deploy OK in chat. Phases
3–5 never create or switch branches. Agents may edit `tasks/` but never commit it (the PM does;
a merge of `origin/master` in Conflicts authors nothing there). Writing agents run one at a time
in the main checkout, never with `isolation: worktree`.

## 1. Issue — the spec

1. Read `tasks/lessons.md` (if it exists) for past corrections.
2. Clarify intent with the user until you can state: what the user sees, where it lives in the
   UI, what persists, and what is out of scope. Ask one question at a time; prefer
   multiple choice.
3. `dcal-scout` (briefed by the PM) locates the closest existing feature and reads it
   end-to-end — new code must look like it (`dcal-recipes` lists worked examples). Map it with
   the code graph first (`code-graph` skill): `.claude/tools/graph-calls.py <dir> [--grep name]`
   gives the chain across layers with node ids; read only the lines it cites. Check
   `graphify-out/memory/` for an earlier trace of the same flow.
4. From the scout's report, tick the layers touched in the issue's Risks list: QML only; UI
   setting (`SettingsData` — daemon reads it too?); IPC method; DB schema change / migration
   (**one-way door — explicit user approval**); provider (google/caldav/microsoft/evolution/
   local/ical); background engine (`core/internal/{sync,reminders,invitations}`); HTTP API / CLI.
   For each existing function you will change, list its callers in the same Risks section.
   Use the `<-` and `~ call sites` lines from `graph-calls.py`, plus
   `graphify affected <node-id> --relation calls --depth 3` for transitive callers. Grep for
   interface implementations and callbacks, which the graph can't see.
5. Write the issue body with `write-issue`'s template (8 headings). **Show it to
   the user and get their yes before creating the issue.**

## 2. Branch

The PM creates the issue, the branch (`gh issue develop … --checkout`, from a clean, current
`master`) and `tasks/<N>-<slug>/todo.md` with its `tasks: plan for <slug>` commit — exact
commands in `project-manager` step 2. Phase 3 starts on that branch.

## 3. Implement

- Follow `dcal-recipes` for each layer. Backend first (method + test), then QML.
- Go changes get tests in the same commit (TDD where practical: failing test first).
- Every new user-facing string: `I18n.tr("…", "context")`, then `make i18n-extract` and commit
  the `translations/en.json` diff with the change that introduced the strings.
- Commit in small, self-contained steps: `area: lowercase summary`. Edit `tasks/` if the task
  needs it but never commit it (the PM does). No `#N` or `Closes #N` in feature commits:
  cherry-picked upstream, `#N` would point at the wrong issue; only the PR body references it.
- If something goes sideways (design doesn't fit, unexpected complexity): stop, tell the PM,
  who updates the issue and re-checks with the user.

## 4. Verify

Run the `verify-change` skill. All checks must pass, and the feature must be seen working in a
**dev instance** (`verify-change` section 4) — never `deploy-local`, which installs only
`master` after a merge. A docs-only change needs only `verify-change` section 0. The PM posts the
verifier's report as an issue comment (`project-manager` step 4's format, which also says when
review is skipped).

## 5. Review

When `project-manager`'s review rule calls for it (otherwise optional), dispatch `dcal-reviewer`
on `git diff master...HEAD` with the issue number, so it checks the acceptance criteria and
CLAUDE.md's rules. Fix real findings; re-run `verify-change`. The PM posts the findings and how
they were resolved as an issue comment.

## 6. Pull request, merge and deploy

The owner reviews every change as a PR on `valicaa/dankcalendar` and merges it on GitHub (merge
commits only; GitHub then deletes the remote branch) — the OK to deploy, never asked in chat.
`<branch>` is `<feat|fix|chore>/<N>-<slug>`. Each block is one Bash call in the main checkout;
one that changes it starts with a guard line. A `STOP` is a failed step to report to the PM.

**6.1 Result (PM).** Commit `tasks/` notes on the feature branch as `tasks: result for <slug>`
(skipped when `git status --short tasks/` prints nothing). Write the PR body to
`<scratchpad>/pr-<N>.md`, linking the evidence comments by the URLs `gh issue comment` printed:

```markdown
Closes #<N>

<what changed, 2–5 lines>

Evidence:
- Verifier: <verdict> — <comment URL>
- Reviewer: <verdict> — <comment URL>, or: skipped — <why> — <the verifier comment URL>

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

**6.3 Hand over (PM).** Post `PR: <URL>` with
`gh issue comment <N> -R valicaa/dankcalendar --body-file <scratchpad>/pr-link.md`, then give
the owner the URL. The next feature may start now; this PR waits for the owner.

**Review requests.** The PM learns of them from the owner or from
`gh pr view <PR> -R valicaa/dankcalendar --json state,reviewDecision,reviews,comments`. Phases
3–5 run again on the same branch, once the checkout is on `master` (a feature being worked
reaches its PR first). `dcal-builder` checks the branch out again (the pull picks up anything
pushed to it on GitHub, e.g. its "Update branch" button):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git switch <branch> || exit 1
git pull --ff-only origin <branch>
```

Fixes are new commits, never a rewrite; a lesson from the round rides in the PM's next `tasks:`
commit on the branch. The PM posts the new evidence on the issue and links it on the PR
(`gh pr comment <PR> -R valicaa/dankcalendar --body-file <scratchpad>/pr-round.md`). Then
`dcal-builder` runs 6.2's push block (it updates the PR; no second `gh pr create`) and its
return to `master`.

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
It keeps both sides and authors nothing under `tasks/`, so the builder commits it. If the hook
blocks it over the merged-in files (reviewed on `master` already), `check-docs.py --ack` and
commit again. On a STOP the PM briefs `dcal-builder` (or `dcal-architect`) to resolve the code
conflict by hand, then phases 4–5 again. Finish with 6.2's push block and return to `master`.

**6.4 After the merge (`dcal-builder`).** The PM learns of the merge from the owner, or from
`gh pr view <PR> -R valicaa/dankcalendar --json state,mergeCommit` (`"state":"MERGED"`; the
merge commit's `oid` is `<M>`), and briefs this with `<M>` once the checkout is on `master`;
each merged PR gets its own 6.4. Pull and delete the merged local branch (`-d` refuses a branch
whose commits aren't all in `master`; a failed deploy's fix gets a new branch anyway):

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git fetch --prune origin
git pull --ff-only origin master
git merge-base --is-ancestor <M> HEAD || { echo "STOP: <M> is not on master"; exit 1; }
git branch -d <branch>
```

Then `verify-change` section 0's docs-only test, on the merge:

```bash
git diff --name-only <M>~1..<M> | grep -vE '^(\.claude/|tasks/|CLAUDE\.md$|\.graphifyignore$|\.github/ISSUE_TEMPLATE/|[^/]+\.md$)'
```

- No output: docs-only, nothing to deploy.
- Any output: run `deploy-local` (it stops during a deploy freeze, below), then
  `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`. If
  `git diff --name-only <M>~1..<M> -- '*.qml'` lists files, say so: the PM offers the owner the
  QML refresh (`code-graph`; it costs LLM tokens).

Report `<M>`, the branch deletion and the deploy output with the previously deployed commit
`<C>` that `deploy-local` step 2 printed. `dcal-verifier` confirms the deploy (version, service,
screenshot); the PM posts `<M>` plus that confirmation, or "docs-only", on the closed issue.

**If the deploy fails** — `deploy-local` errors, or `dcal-verifier` can't confirm it:

1. `dcal-builder` runs `deploy-local`'s Rollback, reinstalling `<C>` from the deploy report.
   `master` is never reset: it moves only by merged PRs.
2. The PM reopens the issue, freezes deploys (`deploy-local` and `sync-upstream` stop while an
   open issue has the label) and posts the evidence: `gh issue reopen <N> -R valicaa/dankcalendar`,
   `gh issue edit <N> -R valicaa/dankcalendar --add-label deploy-failed`, and
   `gh issue comment <N> -R valicaa/dankcalendar --body-file <scratchpad>/deploy-failure.md`.
3. The fix goes up as a new PR from a new branch for the same issue, which the PM creates as in
   phase 2, named `fix/<N>-<slug>-2` (`-3` for a third round) whatever the first prefix was:
   `gh issue develop <N> -R valicaa/dankcalendar --name fix/<N>-<slug>-2 --base master --checkout`.
   Phases 3–6 run again on it; its PR body starts with `Closes #<N>` too, so its merge closes
   the issue and lifts the freeze for its own 6.4. Once `dcal-verifier` confirms that deploy,
   the PM runs `gh issue edit <N> -R valicaa/dankcalendar --remove-label deploy-failed`.

**PR closed without merging.** The issue stays open (redone on a new `<prefix>/<N>-<slug>-2`
branch) unless the owner says the change is dropped; then the PM comments why (`--body-file`)
and runs `gh issue close <N> -R valicaa/dankcalendar --reason "not planned"`.
Either way `dcal-builder` deletes the local branch — only if every commit on it is on origin;
the remote branch stays, so the PR can be reopened:

```bash
[ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
git fetch origin
[ "$(git rev-parse <branch>)" = "$(git rev-parse origin/<branch>)" ] || { echo "STOP: <branch> has commits that aren't on origin"; exit 1; }
git branch -D <branch>
```

## 7. Offer upstream

If the issue's Constraints says "Upstream-worthy: yes", offer to run `upstream-pr` once the fork
PR is merged. Never open an upstream PR without the user's go-ahead.

## Lessons

When the user corrects your approach, add a dated rule to `tasks/lessons.md` (pattern → rule),
committed with the next `tasks:` commit (no feature branch checked out: `project-manager` step 0).
