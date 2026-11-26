# Fork features checklist

What this fork adds on top of upstream, and how to prove each piece still works. A stock
upstream build lacks the fork-only parts (upstream has partial overlaps for #22 and #27, noted
below): replacing the installed binary with an upstream release once silently removed every custom
feature. Fork-only file; upstream has no `FEATURES.md`.

## How to use this file

- After every upstream sync (`sync-upstream` step 3) walk every checkbox below against the merged
  branch, using the offline dev instance (`.claude/tools/dev-instance.sh`, see `verify-change`
  section 4) for the feature checks in part 1. List each entry in the PR body as pass, fail or
  unverified (say why). Part 2 entries read `pending deploy` until the deploy.
- After every `deploy-local` walk every checkbox again on the real desktop. Part 2 can only be
  checked there, not in the dev instance.
- The dev instance is offline on a copy of the real data: local calendars still write, remote
  ones fail with a network error, and nothing reaches Google. Checks that need a live provider or
  a specific error (reconnect, generic) need a test account or a Go test, or stay `unverified`.
- A feature that adds, changes or removes a custom behaviour adds or edits its entry in the same
  PR. A checkbox must say what to open and what you must see.
- Use synthetic or test calendars for the checks. Looking up a real colleague needs the owner's
  separate OK.

## 1. Fork features (user-visible)

### RSVP chip styling (#22)

- [ ] Links: [issue #22](https://github.com/valicaa/dankcalendar/issues/22), [PR #24](https://github.com/valicaa/dankcalendar/pull/24).
- **What it does:** shows your own RSVP on every event chip in all views. Accepted, no-RSVP and
  unknown events get a solid calendar-colour fill with contrast-picked text. Tentative gets a
  light fill plus hatch, needs-action an outline only, declined a faint fill with a struck title.
- **Different from upstream:** upstream #114 (declined styling) is translucent and has no solid
  accepted fill and no shared chip background. Ours keeps the RSVP fill and hatch under hover and
  selection through the shared `EventChipBackground`. Taking upstream's version unchanged loses
  the solid accepted fill.
- **Settings / IPC:** none. Uses the existing `myResponse` field; helpers are `Theme.rsvp*` and
  `Theme.toColor`.
- **Main files:** `quickshell/Common/Theme.qml`, `quickshell/Widgets/EventChipBackground.qml`,
  `quickshell/Modules/views/{MonthView,WeekView,DayView,AgendaView,MonthDayPopover}.qml`.
- [ ] **Check:** with a test calendar holding an accepted, a tentative, an unanswered and a
  declined invitation, open Month, Week, Day, Agenda and the Month "+N more" popover. You must
  see four distinct looks, accepted as a solid fill, for timed and all-day chips in a light and
  a dark theme. Hover and select each one: the fill and
  hatch stay and the selection ring stays visible. The declined event stays shown.

### People search / colleague schedules (#25)

- [ ] Links: [issue #25](https://github.com/valicaa/dankcalendar/issues/25), [PR #26](https://github.com/valicaa/dankcalendar/pull/26).
- **What it does:** type a colleague's email in the sidebar People section to overlay their shared
  events (or busy spans only) on Month, Week and Day. A meeting shared by several people becomes
  one chip with participant stripes; Day shows one lane per person. Google accounts only.
- **Different from upstream:** no upstream equivalent. Upstream's `mergeDuplicateEvents` (#133)
  merges stored copies only and does not replace the transient People merge.
- **Settings / IPC:** IPC method `people.schedule` (capability `people`, range at most 62 days);
  extra Google OAuth scope `calendar.events.freebusy`. No saved setting.
- **Main files:** `core/internal/calendar/schedule.go`, `core/internal/ipc/people.go`,
  `core/internal/providers/google/schedule.go`, `core/internal/oauth/google.go`,
  `quickshell/Services/PeopleService.qml`, `quickshell/Modules/CalendarSidebar.qml`,
  `quickshell/Widgets/{PersonChip,PersonEventChip,BusyBand,AttendeeStripes}.qml`.
- [ ] **Check:** `dev-instance.sh ipc people.schedule` answers with a validation error such as
  "email must be a single address", not "unknown method". `make test` covers the IPC and
  provider side. The overlay itself needs a Google test account (unverified without one): add a colleague under People: Week and Month show their events or Busy bands and your
  other events fade. Add a second person sharing a meeting: one chip with stripes (merged by
  iCalUID plus original start; busy, private or UID-less items never merge). After a sync, repeat
  with the `mergeDuplicateEvents` setting on and off: the stripes stay. Day shows an
  own lane plus one lane per person. Changing month refetches, × removes one person, Esc clears
  all. A bad, duplicate or own address shows a validation message. Overlay chips cannot be
  selected, edited, dragged or deleted.

### Calendars grouped by account, per-account collapse (#27)

- [ ] Links: [issue #27](https://github.com/valicaa/dankcalendar/issues/27), [PR #30](https://github.com/valicaa/dankcalendar/pull/30).
- **What it does:** My calendars is grouped by account. Each account header carries the provider,
  warnings and a ⋯ menu (Sync now, Reconnect when needed, New calendar… for local, Remove…).
  Clicking or pressing a key on a header folds that account, and the fold survives restarts.
  Shown calendars sort before hidden ones.
- **Different from upstream:** upstream #115 groups calendars too, but has no collapse, no account
  controls in the group header, drops empty accounts, and keeps a separate Accounts section. Ours
  keeps empty accounts (with a "No calendars" line) and has no Accounts section.
- **Settings / IPC:** UI setting `collapsedAccounts` (list of account IDs, default `[]`); helpers
  `isAccountCollapsed` and `setAccountCollapsed`. No IPC.
- **Main files:** `quickshell/Modules/CalendarSidebar.qml`, `quickshell/Common/SettingsData.qml`.
- [ ] **Check:** with two accounts plus a local one, My calendars shows one header per account and
  no separate Accounts section. Hiding a calendar moves it below its shown siblings. Collapse an
  account, restart the dev instance, it is still folded (`collapsedAccounts` in
  `ui-settings.json` holds its ID). Expand it from the keyboard. The ⋯ menu offers Sync now and
  Remove…, plus Reconnect on an account with a warning and New calendar… on the local one; Add
  account sits at the bottom. A task-only, sync-disabled or empty account still shows its header.

### Friendly save errors with retry (#29)

- [ ] Links: [issue #29](https://github.com/valicaa/dankcalendar/issues/29), [PR #35](https://github.com/valicaa/dankcalendar/pull/35).
- **What it does:** a failed create, update, delete or RSVP says why in plain words, keeps your
  edits, and offers Try again or Reconnect. A create retry reuses the same event ID, so Google
  never gets two events.
- **Different from upstream:** no upstream equivalent (upstream shows the raw error).
- **Settings / IPC:** additive `errorCode` on write errors (`network`, `unavailable`, `reconnect`,
  `generic`; the raw `error` stays). `events.create` accepts an optional client `uid` (5–1024
  base32hex characters). Google only turns a 409 `duplicate` into an update; other 409s fail.
- **Main files:** `core/internal/calendar/event_id.go`, `core/internal/ipc/{events_write,write_errors}.go`,
  `core/internal/providers/google/provider.go`, `quickshell/Services/DankCalService.qml`,
  `quickshell/Modals/EventDetailsModal.qml`.
- [ ] **Check:** `make test` passes the write-error, event-ID and Google write tests (stable UID,
  duplicate-only 409, `errorCode` next to the raw `error`). In the dev instance edit an event on a
  remote (non-local) calendar, since offline only remote writes fail, and press Save.
  The dialog stays open with your edits, a plain message and Try again, and no URL dump. A failed
  delete or RSVP toast offers a retry that still targets the original event after you open
  another one. A reconnect-type failure offers Reconnect; an unknown one shows a generic message.
  Not covered: Microsoft creates are not duplicate-safe (open #34).

### Friendly batch errors with failed-item retry (#33)

- [ ] Links: [issue #33](https://github.com/valicaa/dankcalendar/issues/33), [PR #36](https://github.com/valicaa/dankcalendar/pull/36).
- **What it does:** keyboard or context-menu delete, drag move, copy/paste, duplicate and
  cut/paste over several events report how many failed and why, and Try again resends only the
  failed items. Cut deletes an original only after its copy exists.
- **Different from upstream:** no upstream equivalent.
- **Settings / IPC:** none. Uses the single-event write methods and the #29 error classes.
- **Main files:** `quickshell/Services/DankCalService.qml`, `quickshell/Widgets/EventSelectionModel.qml`.
- [ ] **Check:** select several events on a remote calendar in the offline dev instance and press
  Delete: the toast
  shows the failed count, a reason and Try again. Paste events into a remote and a local calendar
  (the local ones succeed, the remote ones fail): Try again resends only the failed ones. Cut and paste with a failed copy leaves the
  original in place.

## 2. Desktop integration outside this repo

An update can break these even when the repo is fine. They can only be checked on the real
desktop, after `deploy-local`. Paths are on this machine.

- [ ] **Installed binary:** `~/.local/bin/dcal` is built from this repo by `deploy-local`. Never
  replace it with an upstream release binary or a package. Check: `dcal version` shows a build
  from this repo's `master` (commit hash matches), and the five features above are present.
- [ ] **Window class:** the window class is `com.danklinux.dankcalendar` (upstream v2.0.0 changed
  it to `dev.duxlabs.calendar`). It is matched by `toggles.calendar` in
  `~/.config/caelestia/cli.json`, by two window rules in `~/.config/caelestia/hypr-user.lua`
  (workspace `special:calendar`; `opaque = true` and opacity `"1.0 override"`, so the window is
  solid) and by `~/.local/share/applications/com.danklinux.dankcalendar.desktop`
  (`StartupWMClass`). Check: `hyprctl clients` lists the calendar window with that class; the
  window opens on `special:calendar` via Super+C and is fully opaque. If an update renames the
  class, update all four places.
- [ ] **Theme sync:** `~/.local/bin/dcal-theme-sync` maps the Caelestia scheme to 18 colour keys
  in `~/.config/dankcal/caelestia-theme.json`, triggered by `dcal-theme-sync.path`. It is
  deliberately 18 keys: mapping upstream v2's extra keys was tried and the owner preferred the old
  colours. Check: change the Caelestia scheme; the JSON file updates and the calendar recolours,
  with 18 keys.
- [ ] **Service:** `~/.config/systemd/user/dcal.service` runs `dcal run --session --hidden`.
  Check: `systemctl --user is-active dcal` prints `active`, the `ExecStart` line is unchanged, and
  the window stays hidden until toggled. Never re-enable the in-app "Start at login".
- [ ] **Bar widget:** the Caelestia shell fork's `services/CalendarEvents.qml` and
  `services/CalendarMath.js` (in `~/Documents/code/caelestia-shell`) run `dcal ipc calendars.list`
  and `dcal ipc events.list`. They need `calendars.list` items (a bare array) with `id`, `name`, `color`, `hidden`, and
  `events.list` items with `id`, `uid`, `calendarId`, `start`, `end`, `allDay`, `status`,
  `summary`, `meetingUrl`, plus `visibility` once upstream's #132 is synced (not at `master` today). Its duplicate merge (`mergeDuplicates`) mirrors the rule behind upstream's
  `mergeDuplicateEvents` setting (upstream #133, in `DankCalService.qml` once synced); re-check
  it on every upgrade. Check: `dcal ipc calendars.list`
  and `dcal ipc events.list` return those fields, and the bar shows today's events.
- [ ] **Session PATH:** `~/.config/uwsm/env` must keep `$HOME/.local/bin` on `PATH`, or the bar
  cannot find `dcal`. Check: `grep PATH ~/.config/uwsm/env` shows it, and `command -v dcal` in a
  fresh session resolves to `~/.local/bin/dcal`.
