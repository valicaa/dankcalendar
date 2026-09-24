---
name: upstream-pr
description: Use when turning a finished Dank Calendar feature into a pull request against AvengeMedia/dankcalendar — "send this upstream", "open a PR to the original", "contribute this back".
---

# Upstream PR

Upstream reviews strictly and closes PRs that look like unreviewed AI output. Everything
below exists to make the PR look like a careful human contribution. The user owns it.

`dcal-builder` runs this on the PM's brief. Where a step needs the user (rewriting history, the
PR text, opening the PR), stop and return it to the PM, who asks the user and re-briefs.

**Every block below is one self-contained Bash call.** A subagent's cwd and shell variables
don't survive between calls, so type these in literally — never rely on a variable or a `cd`
from an earlier call:
- `<main>` — the main checkout's absolute path (`git rev-parse --show-toplevel` there)
- `<W>` — the worktree's absolute path, `dankcalendar-pr-<slug>` next to `<main>`, written
  out in full (e.g. `/home/nozomi/Documents/code/dankcalendar-pr-add-free-busy-check`)
- `<M>` — the merge commit hash printed in step 1
- `<N>` — the fork issue number, `<slug>` — its slug

## 1. Build a clean branch

Build `pr/<slug>` in its own `git worktree`, not with `git switch` in the main checkout:
`pr/<slug>` is based on `upstream/master`, so it lacks `.claude/tools/check-docs.py`, and
switching the main checkout onto it would delete that file out from under the PreToolUse hook
— every subsequent Bash call would then fail trying to run a hook script that no longer exists
on disk.

The feature's own commits are between the merge commit's two parents, not `master..<branch>`
(the branch is gone or has moved on after merge). Find the merge commit by its `Closes #N`,
anchored so `#7` doesn't also match `#70`:

```bash
git -C <main> fetch upstream
git -C <main> log master --first-parent --merges -E --grep '^[[:space:]]*Closes #<N>$' -1 --format=%H
```

It must print one hash: that is `<M>`. No output means no merge closes #N — stop and report.

Create the worktree and its submodule:

```bash
git -C <main> worktree add -b pr/<slug> <W> upstream/master
git -C <W> submodule update --init --recursive
```

List the feature's commits, oldest first, each classified by what it touches:

```bash
for c in $(git -C <main> rev-list --reverse --no-merges <M>^1..<M>^2); do
  code=$(git -C <main> diff-tree --no-commit-id --name-only -r "$c" -- . ':!tasks' ':!.claude' ':!CLAUDE.md' ':!.graphifyignore')
  fork=$(git -C <main> diff-tree --no-commit-id --name-only -r "$c" -- tasks .claude CLAUDE.md .graphifyignore)
  kind=code; [ -n "$fork" ] && kind=mixed; [ -z "$code" ] && kind=fork-only
  echo "$c $kind $(git -C <main> log -1 --format=%s "$c")"
done
```

Go down the list in order. Skip `fork-only`. Cherry-pick each run of `code` commits:

```bash
git -C <W> cherry-pick <hash> [<hash>…]
```

A `mixed` commit is cherry-picked with `-n`. If it modifies a fork-only file (e.g.
`tasks/lessons.md`), this prints `CONFLICT (modify/delete)` and exits 1 — expected, the next
block resolves it:

```bash
git -C <W> cherry-pick -n <hash>
```

Strip the fork-only paths. A path upstream doesn't have is removed from the index and the
worktree (`git restore` alone isn't enough for a path that shouldn't exist in `pr/<slug>`); a
path upstream does have is reset to upstream's version rather than deleted:

```bash
cd <W> && for p in tasks .claude CLAUDE.md .graphifyignore; do
  if git cat-file -e "upstream/master:$p" 2>/dev/null; then
    git restore --source=upstream/master --staged --worktree -- "$p"; echo "reset $p to upstream"
  else
    git rm -rq --cached --ignore-unmatch -- "$p"; rm -rf -- "$p"
  fi
done; git status --short
```

`git status --short` must now list only staged code changes. A `U` entry left (e.g.
`DU core/…`) is a code conflict — usually the feature builds on another fork-only change — so
stop and report it to the PM. Otherwise commit with the original author and message:

```bash
git -C <W> commit -C <hash>
```

If that message talks about the fork-only files, fix it with
`git -C <W> commit --amend -m "<subject>" -m "<body>"`.

Confirm that nothing fork-only leaked, including a fork issue reference (feature commits never
carry `#N` — only the fork's merge commit does, and that commit isn't cherry-picked). Each
command prints nothing when clean (grep exits 1). Review each hit by eye — a hex colour like
`#333` is a false positive, not a leak:

```bash
git -C <W> diff --name-only upstream/master...HEAD | grep -E '^(tasks/|\.claude/|CLAUDE\.md$|\.graphifyignore$)'
```

```bash
git -C <W> log --format=%B upstream/master..HEAD | grep -niE '#[0-9]+|valicaa/dankcalendar(/issues/|/pull/)[0-9]+|\bGH-[0-9]+'
```

Keep the worktree until the PR is merged or closed on GitHub, not just opened — review fixes
land in it too (step 4). When it's done, remove it (a submodule checkout needs `--force`; the
branch usually isn't locally merged, so needs `-D`):

```bash
git -C <main> worktree remove --force <W>
git -C <main> branch -D pr/<slug>
```

## 2. Polish for review

- Re-read the whole diff (`git -C <W> diff upstream/master...HEAD`) as an upstream reviewer
  would. For a diff, `A...B` means "from the merge base of A and B to B" — only this branch's
  changes, even after upstream moves on; for a log, `A..B` lists the same commits:
  - no narrating comments
  - no dead code
  - no invented APIs
  - the style of the files it touches
  - `I18n.tr` for every string
  - tests for Go changes
- Squash the fixups into logical commits with `area: summary` subjects; rewriting history needs
  the user's OK (via the PM).
- Run `verify-change` in the worktree. Every command runs as `cd <W> && …` (`cd <W>/core && …`
  for the ones run from `core/`), with `upstream/master...HEAD` wherever it says
  `master...HEAD`. Skip its blast-radius step and say so in the report: the code graph and
  `.claude/tools/` exist only in the main checkout. It must pass against `upstream/master`.
- For UI changes, take before/after screenshots with `grim` for the PR body.

## 3. Draft and confirm

Write the PR title and body, and return them to the PM, who shows them to the user **before**
anything is created. The body may reuse the issue's text but must not link the fork issue by
bare `#N` or `Closes #N` — those numbers mean nothing on `AvengeMedia/dankcalendar` and could
hit an unrelated upstream issue:

```
<area>: <summary>

## What
<1–3 sentences on the user-visible change>

## Why
<the problem it solves>

## How
<key implementation points, mention any new IPC methods/settings/migrations>

## Testing
<what was run + manual steps>

<screenshots>

AI disclosure: parts of this change were written with Claude Code; I reviewed and tested all of it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Before pushing anything, re-run the leak grep on the drafted body file itself (no output =
clean):
```bash
grep -niE '#[0-9]+|valicaa/dankcalendar(/issues/|/pull/)[0-9]+|\bGH-[0-9]+' <scratchpad>/pr-body.md
```

## 4. Open it (only after explicit user approval)

```bash
git -C <W> push -u origin pr/<slug>
gh pr create -R AvengeMedia/dankcalendar --head valicaa:pr/<slug> --base master \
  --title "<title>" --body-file <scratchpad>/pr-body.md
```

Report the PR URL. Later review fixes land in the same worktree (`git -C <W> …`) and get
pushed again. Port them back to `master` too (as a new issue-first change), so the fork doesn't
drift. Remove the worktree and branch (step 1) once the PR is merged or closed.
