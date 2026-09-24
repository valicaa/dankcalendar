---
name: sync-upstream
description: Use when pulling new AvengeMedia/dankcalendar commits into the fork — "update from upstream", "get the latest dank calendar", "sync with the original".
---

# Sync with upstream

1. **Start clean.** `git status` must show a clean tree. Stash or commit first, and ask the user
   before stashing.
2. **Fetch and preview:**
   ```bash
   git fetch upstream
   git log --oneline master..upstream/master
   git diff --stat master...upstream/master -- core/ent/migrate/migrations
   ```
   Summarise for the user what's coming in, and flag any new migrations.
3. **Merge into master:**
   ```bash
   git switch master
   git merge upstream/master -m "merge: upstream $(git rev-parse --short upstream/master)"
   git submodule update --init --recursive
   ```
   Resolve conflicts by keeping upstream's version, then re-applying our feature's intent on
   top of it. Fork-only files (`CLAUDE.md`, `.claude/`, `tasks/`, `.graphifyignore`) should never conflict. If they
   do, keep ours.
4. **Verify.** Run the `verify-change` static checks and build, `make test` and `make build`.
   Refresh the code graph with `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`. If upstream changed a lot of
   QML (`.claude/tools/graph-qml.py status`), offer the QML refresh from the `code-graph` skill.
   It costs LLM tokens, so ask first.
5. **Deploy.** Run `deploy-local`, which handles the migration backup.
6. **Push** after the user confirms it works. First check whether upstream's own commits close
   or cross-link a same-numbered fork issue (upstream and fork issue numbers can collide):
   ```bash
   git log --format=%B master..upstream/master | grep -inE '(close|fix|resolve)[sd]? #[0-9]+'
   ```
   Review any hit with the user before pushing, then `git push origin master`.
7. **Update open feature branches.** For each unmerged `feat/*`/`fix/*`/`chore/*` branch, offer
   `git switch <branch> && git merge master`.
8. **Rebase open `pr/*` branches — never in the main checkout.** Each lives in its own
   `git worktree` (see `upstream-pr`); recreate it if missing
   (`git worktree add <path> pr/<slug>`), then rebase inside it and confirm before force-pushing:
   ```bash
   git -C <pr worktree path> rebase upstream/master
   git -C <pr worktree path> push --force-with-lease
   ```
9. If upstream merged one of our PRs, remove its worktree and delete the matching `pr/<slug>`
   branch locally and on `origin`, after confirming with the user.
