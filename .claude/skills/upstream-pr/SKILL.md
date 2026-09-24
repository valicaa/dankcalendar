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
- `<M>` — a merge commit hash printed in step 1 (`<M1> <M2>…` when there are several)
- `<N>` — the fork issue number, `<slug>` — its slug

**Every block starts with a guard line** that `cd`s into the directory it works on and stops
unless that is really the main checkout or the `pr/<slug>` worktree. An empty or wrong path
then prints `STOP: …` and changes nothing — never delete the guard, and treat a `STOP` as a
failed step, not as "no output = clean".

## 1. Build a clean branch

Build `pr/<slug>` in its own `git worktree`, not with `git switch` in the main checkout:
`pr/<slug>` is based on `upstream/master`, so it lacks `.claude/tools/check-docs.py`, and
switching the main checkout onto it would delete that file out from under the PreToolUse hook
— every subsequent Bash call would then fail trying to run a hook script that no longer exists
on disk.

The feature's own commits are between the merge commit's two parents, not `master..<branch>`
(the branch is gone after the merge). The fork's merge commit is GitHub's `<PR title> (#<PR>)`,
whose message is the PR body, starting with `Closes #N` (`new-feature` 6.1). Find it by that
line, anchored so `#7` doesn't also match `#70`:

```bash
cd "<main>" && [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the main checkout"; exit 1; }
git fetch upstream
git fetch origin
git log origin/master --first-parent --merges -E --grep '^[[:space:]]*Closes #<N>$' --reverse --format='%H %s'
```

Each line is one merged PR for #N, oldest first — usually one; a failed deploy's fix PR
(`new-feature` 6.4) adds another. Each hash is an `<M>`. No output means no merge closes #N —
stop and report.

Create the worktree and its submodule (the first line also refuses a `<W>` that exists already
or isn't `…/dankcalendar-pr-<slug>`):

```bash
[[ "<W>" == /*/dankcalendar-pr-<slug> && ! -e "<W>" ]] || { echo "STOP: bad worktree path"; exit 1; }
cd "<main>" && [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the main checkout"; exit 1; }
git worktree add -b pr/<slug> "<W>" upstream/master
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git submodule update --init --recursive
```

List the feature's commits, oldest first, each classified by what it touches (all the
`<M>` hashes from above, in their order):

```bash
cd "<main>" && [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the main checkout"; exit 1; }
for m in <M1> [<M2>…]; do
  git cat-file -e "$m^2" || { echo "STOP: $m is not a merge commit"; exit 1; }
  for c in $(git rev-list --reverse --no-merges "$m^1..$m^2"); do
    code=$(git diff-tree --no-commit-id --name-only -r "$c" -- . ':!tasks' ':!.claude' ':!CLAUDE.md' ':!.graphifyignore')
    fork=$(git diff-tree --no-commit-id --name-only -r "$c" -- tasks .claude CLAUDE.md .graphifyignore)
    kind=code; [ -n "$fork" ] && kind=mixed; [ -z "$code" ] && kind=fork-only
    echo "$c $kind $(git log -1 --format=%s "$c")"
  done
done
```

A `merge: master into <slug>` commit on the branch (`new-feature` Conflicts) is skipped by
`--no-merges`; the `master` commits it brought in are already in `<M>^1`, so they aren't listed.

Go down the list in order. Skip `fork-only`. Cherry-pick each run of `code` commits:

```bash
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git cherry-pick <hash> [<hash>…]
```

A `mixed` commit is cherry-picked with `-n`. If it modifies a fork-only file (e.g.
`tasks/lessons.md`), this prints `CONFLICT (modify/delete)` and exits 1 — expected, the next
block resolves it:

```bash
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git cherry-pick -n <hash>
```

Strip the fork-only paths with git only (no bare `rm -rf`): a path upstream doesn't have is
removed from the index and the worktree; a path upstream does have is reset to upstream's
version rather than deleted:

```bash
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
for p in tasks .claude CLAUDE.md .graphifyignore; do
  if git cat-file -e "upstream/master:$p" 2>/dev/null; then
    git restore --source=upstream/master --staged --worktree -- "$p"; echo "reset $p to upstream"
  else
    git rm -rqf --ignore-unmatch -- "$p"
  fi
done; git status --short
```

`git status --short` must now list only staged code changes. A `U` entry left (e.g.
`DU core/…`) is a code conflict — usually the feature builds on another fork-only change — so
stop and report it to the PM. Otherwise commit with the original author and message:

```bash
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git commit -C <hash>
```

If that message talks about the fork-only files, fix it with
`git commit --amend -m "<subject>" -m "<body>"` (after the same guard line).

Confirm that nothing fork-only leaked, including a fork issue reference (feature commits never
carry `#N` — only the PR body in the fork's merge commit does, and that isn't cherry-picked).
Past the guard, the block prints nothing when clean (both greps exit 1). Review each hit by
eye — a hex colour like `#333` is a false positive, not a leak:

```bash
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git diff --name-only upstream/master...HEAD | grep -E '^(tasks/|\.claude/|CLAUDE\.md$|\.graphifyignore$)'
git log --format=%B upstream/master..HEAD | grep -niE '#[0-9]+|valicaa/dankcalendar(/issues/|/pull/)[0-9]+|\bGH-[0-9]+'
```

Keep the worktree until the PR is merged or closed on GitHub, not just opened — review fixes
land in it too (step 4). When it's done, remove it (a submodule checkout needs `--force`; the
branch usually isn't locally merged, so needs `-D`):

```bash
[[ "<W>" == /*/dankcalendar-pr-<slug> ]] || { echo "STOP: bad worktree path"; exit 1; }
cd "<main>" && [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the main checkout"; exit 1; }
git worktree remove --force "<W>"
git branch -D pr/<slug>
```

## 2. Polish for review

- Re-read the whole diff (the worktree guard line, then `git diff upstream/master...HEAD`) as an
  upstream reviewer would. For a diff, `A...B` means "from the merge base of A and B to B" — only
  this branch's changes, even after upstream moves on; for a log, `A..B` lists the same commits:
  - no narrating comments
  - no dead code
  - no invented APIs
  - the style of the files it touches
  - `I18n.tr` for every string
  - tests for Go changes
- Squash the fixups into logical commits with `area: summary` subjects; rewriting history needs
  the user's OK (via the PM).
- Run `verify-change` in the worktree. Every call starts with the worktree guard line (then
  `cd core && …` for the commands run from `core/`), with `upstream/master...HEAD` wherever it says
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
cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
git push -u origin pr/<slug>
gh pr create -R AvengeMedia/dankcalendar --head valicaa:pr/<slug> --base master \
  --title "<title>" --body-file <scratchpad>/pr-body.md
```

Report the PR URL. Later review fixes land in the same worktree (each call behind the guard line)
and get pushed again. Port them back to `master` too (as a new issue-first change), so the fork
doesn't drift. Remove the worktree and branch (step 1) once the PR is merged or closed.
