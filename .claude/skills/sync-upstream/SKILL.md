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
   top of it. Fork-only files (`CLAUDE.md`, `.claude/`, `tasks/`) should never conflict. If they
   do, keep ours.
4. **Verify.** Run the `verify-change` static checks and build, `make test` and `make build`.
5. **Deploy.** Run `deploy-local`, which handles the migration backup.
6. **Push** after the user confirms it works: `git push origin master`.
7. **Update open feature branches.** For each unmerged `feat/*` branch, offer
   `git switch feat/<slug> && git merge master`. For each open `pr/*` branch, offer
   `git rebase upstream/master` followed by a force-push, and confirm before force-pushing.
8. If upstream merged one of our PRs, delete the matching `pr/<slug>` branch locally and on
   origin, after confirming with the user.
