---
name: deploy-local
description: Use when installing a new Dank Calendar build onto this machine's running desktop calendar — after merging a feature, after syncing upstream, or when the user says "install it", "deploy", "update my calendar".
---

# Deploy to the local desktop

The user's real calendar runs `~/.local/bin/dcal` via `~/.config/systemd/user/dcal.service`
and uses real data in `~/.local/share/dankcal/`. `dcal-builder` runs this on the PM's brief, in
the main checkout, after the user's OK (`new-feature` phase 6, or `sync-upstream`).

## Steps

1. **Check the branch.** Only `master` is deployed: `git branch --show-current` must print
   `master` and `git status --short` nothing. To try out an unmerged branch, use
   `verify-change`'s dev instance instead — never install it here.
2. **Check for migrations.** Compare the migrations this build ships with what the deployed binary last had:
   ```bash
   git diff --name-only "$(~/.local/bin/dcal version | sed -n 's/.*commit \([0-9a-f]*\).*/\1/p')" HEAD -- core/ent/migrate/migrations
   ```
   If any are listed, back up first and tell the user:
   ```bash
   cp -a ~/.local/share/dankcal ~/.local/share/dankcal.bak-$(date +%F-%H%M)
   ```
3. **Build and install:**
   ```bash
   make build
   install -m 755 core/bin/dcal ~/.local/bin/dcal
   systemctl --user restart dcal
   ```
4. **Verify:**
   ```bash
   sleep 3
   systemctl --user is-active dcal
   ~/.local/bin/dcal version            # commit must match `git rev-parse --short=8 HEAD`
   dcal account list                    # accounts load, status ok
   journalctl --user -u dcal -n 30 --no-pager -p warning
   ```
   Then `dcal show` and take a `grim` screenshot. Read it to confirm the window renders.
5. **Report** version, commit, service state, and anything unusual.

## Rollback

Check out the previous good commit detached (a plain `git switch master~1` fails: "a branch is
expected"), then rerun steps 3–4 — the one time step 1's `master` check doesn't apply:

```bash
git switch --detach master~1
```

If a migration ran, stop the service and restore the backup directory before starting the
older binary. Afterwards return with `git switch master`; the installed binary stays the
rolled-back one until the next deploy.

## Don't

- Don't install to `/usr` or use sudo. The AUR package was removed on purpose.
- Don't create `~/.config/autostart/com.danklinux.dankcalendar.desktop`; the systemd unit already starts dcal at login.
