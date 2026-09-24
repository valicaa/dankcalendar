---
name: sync-upstream
description: Use when pulling new AvengeMedia/dankcalendar commits into the fork — "update from upstream", "get the latest dank calendar", "sync with the original".
---

# Sync with upstream

`dcal-builder` runs this on the PM's brief, in the main checkout. Like every change, the sync
reaches `master` as a PR on `valicaa/dankcalendar` that the owner merges on GitHub — here from a
`sync/upstream-<hash>` branch, with no issue — and that merge is the OK to deploy. Every "ask
the user" below means: stop and return the question to the PM, who asks and re-briefs. Each
block is one Bash call; a `STOP` is a failed step.

1. **Start on a clean `master` and preview.** A checked-out feature branch (`new-feature` phases
   2–5) holds the main checkout: wait until its PR is open.
   ```bash
   [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
   git pull --ff-only origin master
   git fetch upstream
   git log --oneline master..upstream/master
   git diff --stat master...upstream/master -- core/ent/migrate/migrations
   git log --format=%B master..upstream/master | grep -inE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]+'
   ```
   No commits listed: nothing to sync, stop. Otherwise report what's coming in, any new
   migration (a one-way door for the real database: the PR body flags it, and the owner's merge
   approves it) and the last command's hits: upstream commits that would close or cross-link a
   same-numbered fork issue once merged (upstream and fork numbers collide); no output means
   none. It must run before step 2: after the merge, `master..upstream/master` is empty.
2. **Branch and merge:**
   ```bash
   [ -f CLAUDE.md ] && [ "$(git rev-parse --show-toplevel)" = "$PWD" ] && [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not the main checkout on a clean master"; exit 1; }
   git switch -c "sync/upstream-$(git rev-parse --short upstream/master)" || exit 1
   git merge upstream/master -m "merge: upstream $(git rev-parse --short upstream/master)"
   git submodule update --init --recursive
   ```
   Resolve conflicts by keeping upstream's version, then re-applying our feature's intent on
   top of it. Fork-only files (`CLAUDE.md`, `.claude/`, `tasks/`, `.graphifyignore`) should
   never conflict. If they do, keep ours: `git checkout --ours -- <path> && git add <path>`.
   Finish with `git commit --no-edit --cleanup=strip` (plain `--no-edit` keeps the
   `# Conflicts:` lines in the message) in its own call — the check-docs hook may ask for
   `.claude/tools/check-docs.py --ack`, as the merged-in upstream files trip its doc rules —
   then run the submodule update above.
3. **Verify** on the branch. Run the `verify-change` static checks and build, `make test` and
   `make build`. Refresh the code graph with
   `GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`. If upstream
   changed a lot of QML (`.claude/tools/graph-qml.py status`), offer the QML refresh from the
   `code-graph` skill. It costs LLM tokens, so ask first.
4. **Open the PR.** The PM writes `<scratchpad>/pr-sync.md`: what's coming in, the flagged
   migrations, the verify results, each closing-keyword hit by commit hash only, then the
   attribution line. Never copy a `Fixes #12`-style line into it: GitHub acts on keywords in a
   PR body, and the body becomes the merge commit's message. Push with `new-feature` 6.2's push
   block (`<branch>` = the `sync/upstream-<hash>` branch step 2 made), open the PR, then return
   to `master` with 6.2's last block:
   ```bash
   gh pr create -R valicaa/dankcalendar --base master --head sync/upstream-<hash> --title "merge: upstream <hash>" --body-file <scratchpad>/pr-sync.md
   ```
   The PM gives the owner the link.
5. **After the owner merges**, `new-feature` 6.4 applies as written: pull, delete the branch,
   `deploy-local` (it handles the migration backup), `dcal-verifier` confirms. A failed deploy
   is rolled back the same way; with no issue to reopen, the PM opens a `bug` issue for the fix.
6. **Update the feature in flight.** If a feature's PR is open, offer merging `origin/master`
   into its branch with `new-feature`'s Conflicts procedure (merge, then push) — needed when
   the PR shows a conflict, otherwise only to re-verify it against the new upstream.
7. **Rebase open `pr/*` branches — never in the main checkout.** Each lives in its own
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
8. If upstream merged one of our PRs, remove its worktree and delete the matching `pr/<slug>`
   branch locally and on `origin`, after confirming with the user.
