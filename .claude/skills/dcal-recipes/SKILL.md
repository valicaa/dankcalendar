---
name: dcal-recipes
description: Use when implementing a piece of a Dank Calendar feature — adding an IPC method, a UI setting, a settings page, a daemon-read setting, an HTTP endpoint, a DB schema change/migration, a QML view or modal, or a Go test. Gives the exact files and patterns this codebase uses, with a worked example for each.
---

# Dank Calendar implementation recipes

Always open the worked example and copy its shape. New code should be indistinguishable
from what's already there. To see a worked example's full chain without reading whole
files, run `.claude/tools/graph-calls.py <file-or-dir> --grep <name>`. For example,
`graph-calls.py quickshell/Services/DankCalService.qml --grep autostart` shows the QML function,
the IPC method string and the Go `case` that handles it.

## A. New IPC method (UI ↔ daemon)

Worked example: `system.autostart.get/set`.

1. **Registry.** Add a `MethodSpec` to `Methods` in `core/internal/ipc/registry.go`, next to its
   group:
   `{Name: "group.thing.do", Group: "group", Desc: "…", Params: []ParamSpec{req("id", ""), opt("limit", "")}}`.
   The registry feeds `dcal ipc list`, shell completion and `describe`. There's no separate docs file.
2. **Handler.** Add a `case` to the group's switch: `system.go`, `handlers.go` (calendars/events),
   `tasks.go`, `accounts.go`, `ui.go` or `reminders.go`. Read params with `ParamString`,
   `ParamInt`, `ParamBool` or `ParamStringSlice` (from `models.go`). Reply with
   `Respond(w, req.ID, map[string]any{…})` or `RespondError(w, req.ID, msg)` and `return`
   early. Validate required params explicitly, the way `system.openUri` checks `uri`.
3. **New prefix group:** add a `strings.HasPrefix` case in `router.go`.
4. **New dependency:** add a field to `Deps` (`deps.go`), wire it in `cmd/dcal/daemon.go`
   (`bootDaemonServices`), and nil-check it in the handler (see `deps.ColorScheme`).
5. **Tell the UI:** if other views must refresh, `deps.Bus.Publish(topic, payload)`. The UI subscribes
   to `accounts, calendars, events, tasks, sync, ui, colorScheme`. A new topic also needs
   handling in `_handleEvent` in `DankCalService.qml`.
6. **Test** in `core/internal/ipc/*_test.go` with the `routeAndRead(t, Request{…}, deps)` helper
   from `router_test.go`. Cover success, a missing param and a nil dependency.
7. **QML client.** Add a function to `quickshell/Services/DankCalService.qml` shaped like
   `setAutostart`: `sendRequest("…", {params}, response => { if (response.error) lastError = response.error; else …; if (callback) callback(response); })`.
   If it's state, add a `property` and a `refreshX()` called on connect (~line 118).
8. Try it: `dcal ipc group.thing.do id=… ` against the dev daemon.

`ParamSpec` has a naming trap. Inside handlers, `req` is the Request, which shadows the `req()` helper. Only call
`req()`/`opt()` in `registry.go`.

## B. UI-only setting

Worked example: `showWeekNumbers`.

1. `quickshell/Common/SettingsData.qml`: add `property <type> foo: <default>` inside
   `JsonAdapter { id: adapter }` (~line 240+), and `property alias foo: adapter.foo` with
   the other aliases (~line 80+). Keep related settings grouped.
2. Bind it in `quickshell/Modals/SettingsContent.qml` in the right page section with a
   `SettingsToggleRow`, `SettingsDropdownRow` (or the file-local `OptionDropdownRow`), `SettingsSliderRow` or similar:
   `checked: SettingsData.foo` / `onToggled: checked => SettingsData.foo = checked`.
   Label and description both go through `I18n.tr(…, "foo setting label|description")`.
3. Read `SettingsData.foo` where it applies (for the example: `Modules/views/MonthView.qml`).
4. Run `make i18n-extract`.

## C. Setting the daemon also reads

Worked example: `syncIntervalMinutes`.

Do everything in B, then:
1. Add a field with a json tag identical to the QML property name to `UISettings` in
   `core/internal/settings/settings.go`.
2. Set the same default in `Defaults()`. The QML adapter and Go defaults must match.
3. Read it with `settings.Load().Foo` at the point of use. It's re-read on demand and never cached
   (see `syncEngine.SetIntervalFunc` in `cmd/dcal/daemon.go`).
4. Add a test for the default and for parsing in `internal/settings`.

## D. New settings page

In `quickshell/Modals/`:
1. `SettingsContent.qml`: add a `Component { id: fooPage; SettingsPage { … } }`, and a `case` in
   the page `Loader` switch with the next index.
2. `SettingsSidebar.qml`: add an entry to `groups`, `{accent, index, label, hint, icon}`, with the
   same index. The label and hint go through `I18n.tr`.

## E. QML view, widget, or modal

- Views live in `quickshell/Modules/views/` and are instantiated in `Modules/CalendarContent.qml`.
- Modals live in `quickshell/Modals/` and are `Loader`s in `Modules/CalendarWindow.qml` (~line 895+),
  opened with `xLoader.active = true; xLoader.item.show()`.
- Reusable app widgets go in `quickshell/Widgets/`. Check DankCommon first
  (`dank-qml-common/DankCommon/Widgets/`: `DankIcon`, `DankButton`, `DankToggle`,
  `DankDropdown`, `DankListView`, `DankFlickable`, `StyledText`, `StyledRect`, …). Never add raw
  `ListView`/`Flickable`/`ScrollView` where a Dank* wrapper exists.
- Imports: `qs.Common`, `qs.Services`, `qs.Widgets`, `qs.Modals`, `qs.Modules`,
  `qs.DankCommon.Widgets`.
- Styling: take colours, spacing, radii and fonts from `Theme`, never hard-coded values. Animations go through `Anims`.
- Logging: `readonly property var log: Log.scoped("ComponentName")`. `console.*` is rejected by
  pre-commit.
- Event helpers (time formatting, all-day handling) are in `Common/EventUtils.js`. Reuse them.
- Iterate with hot reload (see `verify-change`).

## F. DB schema change (one-way door)

**Get explicit user approval first.** Once deployed, it migrates the user's real database.

1. Edit `core/ent/schema/<entity>.go`.
2. `make generate` regenerates `core/ent/`. Commit the generated code.
3. `make migrate name=add_foo_to_bar` writes `core/ent/migrate/migrations/<ts>_add_foo_to_bar.sql`
   (goose format) plus `atlas.sum`. Review the SQL by hand. SQLite table rebuilds must not
   lose child rows (see issue #76; migrations run with `foreign_keys(OFF)`).
4. After a hand-edited or hand-written migration, run `make migrate-checksum`.
5. Add repo methods in `core/repo/<entity>_queries.go` or `<entity>_mutations.go`, using an `XxxInput`
   struct for writes and `WithTx` for multi-step writes.
6. Test with `repo.New(client)` over `repo.OpenMemory(ctx)`, which runs every migration.
7. `deploy-local` backs up the DB automatically when it sees new migrations.

## G. HTTP endpoint (external API only, the UI doesn't use it)

Worked example: any route in `core/api/calendar/handlers.go`.

1. In `RegisterHandlers`: `huma.Register(grp, huma.Operation{OperationID: "kebab-id", Summary: "…", Method: http.MethodGet, Path: "/…"}, h.Method)`,
   with input and output structs that have a `Body` field.
2. Test in `handlers_test.go`'s `HandlersSuite` (`humatest`, `repo.OpenMemory`, `seedAccount` and
   `seedCalendar` helpers).

## H. CLI subcommand

Cobra commands live in `core/cmd/dcal/` (see `reminders.go` or `sync.go`). They talk to the running
daemon over IPC, so add the IPC method (A) first and call it from the command.

## I. Go tests in general

- testify `require`/`assert`. Use `suite` when setup is shared (`internal/sync/engine_test.go`).
- Table-driven tests for pure functions.
- No network or system services. Use `t.TempDir()`, `httptest`, and `_ "time/tzdata"` for named zones.
- Mock through mockery. Add the interface to `core/.mockery.yml`, then `make mocks`
  (the config uses mockery v3 syntax: `go install github.com/vektra/mockery/v3@latest` if it's missing). Use the expecter API:
  `m.EXPECT().Foo(mock.Anything).Return(…)`.
