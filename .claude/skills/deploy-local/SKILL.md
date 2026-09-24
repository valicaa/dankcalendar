---
name: deploy-local
description: Use when installing a new Dank Calendar build onto this machine's running desktop calendar — after the owner merged a feature or upstream-sync PR, or when the user says "install it", "deploy", "update my calendar".
---

# Deploy to the local desktop

The user's real calendar runs `~/.local/bin/dcal` via `~/.config/systemd/user/dcal.service`
and uses real data in `~/.local/share/dankcal/`. `dcal-builder` runs this on the PM's brief, in
the main checkout, once the owner has merged the PR on GitHub (`new-feature` 6.4, or
`sync-upstream` step 5) — that merge is the OK, nobody asks again in chat.

## Steps

1. **Check the freeze and the branch.** No deploy while an open issue carries `deploy-failed`
   (a failed deploy waits for its fix PR, `new-feature` 6.4), and only a clean `master` is
   deployed — to try out an unmerged branch, use `verify-change`'s dev instance instead:
   ```bash
   [ "$(gh issue list -R valicaa/dankcalendar --label deploy-failed --state open --json number -q length)" = 0 ] || { echo "STOP: deploy freeze - an open deploy-failed issue waits for its fix"; exit 1; }
   [ "$(git branch --show-current)" = master ] && [ -z "$(git status --short)" ] || { echo "STOP: not on a clean master"; exit 1; }
   ```
   A `gh` failure prints nothing, which also stops: never deploy without the check.
2. **Check for migrations.** Compare the migrations this build ships with what the deployed
   binary last had:
   ```bash
   C=$(~/.local/bin/dcal version | sed -n 's/.*commit \([0-9a-f]*\).*/\1/p'); [ -n "$C" ] && git cat-file -e "$C^{commit}" || { echo "STOP: deployed commit unknown - treat every migration as new, back up first"; exit 1; }
   echo "previously deployed: $C"
   git diff --name-only "$C" HEAD -- core/ent/migrate/migrations
   ```
   Put the `previously deployed` hash (`<C>`) in the deploy report: it is the rollback target.
   If any migrations are listed, or the first line stopped, back up first and tell the user:
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

Reinstall the previously deployed commit `<C>` that step 2 printed (if step 2 stopped with the
deployed commit unknown, use `<M>~1`, `master` before the merge, and say so). Check it out
detached (a plain `git switch <C>` fails: "a branch is expected"), then rerun steps 3–4 — the
one time step 1 doesn't apply:

```bash
git switch --detach <C>
```

If a migration ran, stop the service and restore the backup directory before starting the
older binary. Afterwards return with `git switch master`; the installed binary stays the
rolled-back one until the next deploy. `master` itself is never reset — it moves only by merged
PRs — so the fix goes up as a new PR (`new-feature` 6.4, "If the deploy fails").

## Don't

- Don't install to `/usr` or use sudo. The AUR package was removed on purpose.
- Don't create `~/.config/autostart/com.danklinux.dankcalendar.desktop`; the systemd unit already starts dcal at login.
