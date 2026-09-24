---
name: sync-upstream
description: Use when pulling new AvengeMedia/dankcalendar commits into the fork — "update from upstream", "get the latest dank calendar", "sync with the original".
---

# Sync with upstream

`dcal-builder` runs this on the PM's brief, in the main checkout. Every "ask the user" or
"confirm" below means: stop and return the question to the PM, who asks and re-briefs.

1. **Start clean.** `git status --short` must print nothing. Stash or commit first, and ask the
   user before stashing. Note the current branch (`git branch --show-current`); if a feature is
   in flight, step 7 returns to it.
2. **Fetch and preview:**
   ```bash
   git fetch upstream
   git log --oneline master..upstream/master
   git diff --stat master...upstream/master -- core/ent/migrate/migrations
   git log --format=%B master..upstream/master | grep -inE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]+'
   ```
   Summarise for the user what's coming in, and flag any new migrations. The last command
   lists upstream commits that would close or cross-link a same-numbered fork issue once pushed
   (upstream and fork issue numbers collide); no output means none. It must run before step 3:
   after the merge, `master..upstream/master` is empty.

   **Stop here** and return the preview to the PM. Steps 3–6 (merge, verify, deploy, push)
   continue only on the user's OK, relayed by the PM — one OK covers the merge and the deploy.
3. **Merge into master:**
   ```bash
   git switch master
   git pull --ff-only origin master
   [ "$(git rev-list --count origin/master..master)" = 0 ] || { echo "STOP: master has unpushed commits"; exit 1; }
   git merge upstream/master -m "merge: upstream $(git rev-parse --short upstream/master)"
   git submodule update --init --recursive
   ```
   Resolve conflicts by keeping upstream's version, then re-applying our feature's intent on
   top of it. Fork-only files (`CLAUDE.md`, `.claude/`, `tasks/`, `.graphifyignore`) should
   never conflict. If they do, keep ours: `git checkout --ours -- <path> && git add <path>`.
   Finish with `git commit --no-edit --cleanup=strip` (plain `--no-edit` keeps the
   `# Conflicts:` lines in the message), then run the submodule update above.
4. **Verify.** Run the `verify-change` static checks and build, `make test` and `make build`.
   Refresh the code graph with
   `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`. If upstream
   changed a lot of QML (`.claude/tools/graph-qml.py status`), offer the QML refresh from the
   `code-graph` skill. It costs LLM tokens, so ask first.
5. **Deploy.** Run `deploy-local` on `master`; it handles the migration backup.
6. **Push** after the user confirms it works and has reviewed any closing-keyword hit from
   step 2 — only the upstream merge may ride out, never a leftover unpushed commit:
   ```bash
   [ "$(git branch --show-current)" = master ] && [ "$(git rev-list --first-parent --count origin/master..master)" = 1 ] && git log -1 --format=%s | grep -q '^merge: upstream ' || { echo "STOP: master holds more than the upstream merge"; exit 1; }
   git push origin master
   ```
7. **Update open feature branches.** For each unmerged `feat/*`/`fix/*`/`chore/*` branch, offer
   `git switch <branch> && git merge master`. End on the branch noted in step 1.
8. **Rebase open `pr/*` branches — never in the main checkout.** Each lives in its own
   `git worktree` (see `upstream-pr`, whose `<main>`/`<W>` placeholders and guard lines apply
   here: literal absolute paths, one self-contained Bash call per block, and a `STOP` means
   the step failed). Recreate a missing one first:
   ```bash
   [[ "<W>" == /*/dankcalendar-pr-<slug> && ! -e "<W>" ]] || { echo "STOP: bad worktree path"; exit 1; }
   cd "<main>" && [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the main checkout"; exit 1; }
   git worktree add "<W>" pr/<slug>
   cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
   git submodule update --init --recursive
   ```
   Then rebase inside it:
   ```bash
   cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
   git rebase upstream/master
   git submodule update --init --recursive
   ```
   and confirm with the user before force-pushing:
   ```bash
   cd "<W>" && [ "$(git branch --show-current)" = "pr/<slug>" ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "STOP: not the pr/<slug> worktree"; exit 1; }
   git push --force-with-lease origin pr/<slug>
   ```
9. If upstream merged one of our PRs, remove its worktree and delete the matching `pr/<slug>`
   branch locally and on `origin`, after confirming with the user.
