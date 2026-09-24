---
name: upstream-pr
description: Use when turning a finished Dank Calendar feature into a pull request against AvengeMedia/dankcalendar — "send this upstream", "open a PR to the original", "contribute this back".
---

# Upstream PR

Upstream reviews strictly and closes PRs that look like unreviewed AI output. Everything
below exists to make the PR look like a careful human contribution. The user owns it.

## 1. Build a clean branch

```bash
git fetch upstream
git switch -c pr/<slug> upstream/master
# code commits only, oldest first — skip merges and anything touching fork-only paths
git log --reverse --no-merges --format=%H master..<feat|fix|chore>/<N>-<slug> -- . ':!tasks' ':!.claude' ':!CLAUDE.md' ':!.graphifyignore'
git cherry-pick <those hashes>
```

If a commit mixes fork-only paths with code (check each hash with `git show --stat`), cherry-pick it with `-n`, run
`git restore --staged --worktree -- tasks .claude CLAUDE.md .graphifyignore`, then commit.

Confirm that nothing fork-only leaked, including a fork issue reference (feature commits never
carry `#N`/`Closes #N` — only the fork's merge commit does, and that commit isn't cherry-picked):
```bash
git diff --name-only upstream/master...HEAD | grep -E '^(tasks/|\.claude/|CLAUDE\.md|\.graphifyignore)' && echo LEAK
git log --format=%B upstream/master...HEAD | grep -iE '#[0-9]+|Closes #' && echo "fork issue reference leaked — reword the commit"
```

## 2. Polish for review

- Re-read the whole diff (`git diff upstream/master...HEAD`) as an upstream reviewer would:
  - no narrating comments
  - no dead code
  - no invented APIs
  - the style of the files it touches
  - `I18n.tr` for every string
  - tests for Go changes
- Squash the fixups into logical commits with `area: summary` subjects, and ask the user before
  rewriting history.
- Run `verify-change` on this branch. It must pass against `upstream/master`.
- For UI changes, take before/after screenshots with `grim` for the PR body.

## 3. Draft and confirm

Write the PR title and body, and show them to the user **before** creating anything. The body
may reuse the issue's text but must not link the fork issue by bare `#N` or `Closes #N` — those
numbers mean nothing on `AvengeMedia/dankcalendar` and could hit an unrelated upstream issue:

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

## 4. Open it (only after explicit user approval)

```bash
git push -u origin pr/<slug>
gh pr create --repo AvengeMedia/dankcalendar --head valicaa:pr/<slug> --base master \
  --title "<title>" --body-file <scratchpad>/pr-body.md
```

Before pushing, re-run the grep check above on the drafted PR body file too. Report the PR URL.
Later review fixes go on `pr/<slug>`. Port them back to `<feat|fix|chore>/<N>-<slug>` or
`master` too, so the fork doesn't drift.
