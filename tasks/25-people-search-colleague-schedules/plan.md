# #25 People search for colleague schedules: design and phased plan

Spec: `gh issue view 25 -R valicaa/dankcalendar`. Branch `feat/25-people-search-colleague-schedules`.
No DB migration, no `core/ent/schema` change and no new `Deps` field. Everything below was
checked against the code at `7a1edda`.

## 0. Facts the design rests on (from the code)

- **A reconnect flow already exists end to end.**
  - UI: `DankCalService.reconnectAccount(acc, cb)` (`quickshell/Services/DankCalService.qml:1470`)
    calls `accounts.google.reauth`, opens the browser, then `accounts.google.complete`.
  - Daemon: `handleGoogleReauth` (`core/internal/ipc/accounts.go:76`) builds a new `GoogleFlow`
    from `oauth.GoogleConfig`. The config carries `GoogleScopes()` (`core/internal/oauth/google.go:21-29`)
    and `AuthURL` forces consent (`google.go:77-83`, `oauth2.ApprovalForce`), so a reconnect
    always asks for the *current* scope list.
  - `accounts.FinishGoogle` (`core/internal/accounts/add.go:211`) overwrites the token and
    clears `needs_reauth`.
  - Callers: the sidebar account row (`quickshell/Modules/CalendarSidebar.qml:895`,
    `:1076-1107`) and the settings account row (`quickshell/Modals/SettingsContent.qml:1213-1217`).
- **The stored token does not record which scopes were granted.** `oauth.MarshalToken` is
  `json.Marshal(*oauth2.Token)` (`google.go:103`); the `scope` field of the token response lives
  in the unexported `raw` and is lost. Google's granular consent also lets the user untick a
  scope. So the scopes cannot be read locally. The only reliable signal is a 403
  `insufficientPermissions` at call time. The codebase already detects exactly that for Tasks:
  `isOptionalServiceUnavailable` (`core/internal/providers/google/provider.go:128-147`) leads to
  `NoticeTasksUnavailable` and then the "…or reconnect this account" hint
  (`SettingsContent.qml:46-51`).
- **The scope constant exists:** `gcalendar.CalendarEventsFreebusyScope` (google.golang.org/api
  v0.295.0 `calendar-gen.go:137`). The response to `events.list` carries `AccessRole` (`none` |
  `freeBusyReader` | `reader` | `writerWithoutPrivateAccess` | `writer` | `owner`), so an
  events.list call on the colleague tells "details" from "busy only" without guessing.
- **Owner events have no iCalUID.** `fromGoogleEvent` stores `UID = RemoteID = item.Id`
  (`provider.go:399-417`). Expanded occurrences come back from `repo.listEventsExpanded` with
  `UID = master.UID` and `RecurringID = master.UID`. The first occurrence is the master row
  itself, and exception rows have their own instance id plus `RecurringID`
  (`core/repo/events_queries.go:76-165`).
- **IPC requests run concurrently.** dankgo `ipc/server.go:171` runs `go s.dispatch(...)` per
  request, so a slow Google call does not block other IPC.
- **Many callers use `eventsForDay` / `eventsForRange`, not only views.** These include keyboard
  navigation (`CalendarWindow.qml:76,193,203,254,277`), selection (`Widgets/EventSelectionModel.qml:45,102,278`)
  and the context menu (`Widgets/EventContextMenu.qml:74`). **The overlay must not be mixed into
  them**, or colleague events would become selectable, deletable and keyboard-navigable.
- Test pattern for the Google API: `httptest.NewServer` + `calendar.NewService(ctx,
  option.WithHTTPClient(server.Client()), option.WithEndpoint(server.URL+"/"))` and
  `&Provider{svc: svc, quota: q}` with `fakeQuota()`
  (`core/internal/providers/google/quota_test.go:96-135`). IPC tests use `routeAndRead` (`core/internal/ipc/router_test.go:17`)
  plus a memory repo and a registry built from a mockery `MockProviderFactory`
  (`core/internal/ipc/ics_test.go:30-48,203`).

## 1. Re-consent

**Decision: add the scope to `GoogleScopes()` and reuse the existing reconnect flow. Detect
the missing scope at call time from the 403, and give the UI a `reconnect` status (not an
error).**

- `core/internal/oauth/google.go:21-29`: add `gcalendar.CalendarEventsFreebusyScope`. New logins
  and every reconnect then request it. No other OAuth code changes.
- Existing refresh tokens keep working for sync (the old scopes are unchanged). Only
  `freebusy.query` fails, with 403 `insufficientPermissions`. `events.list` on a colleague who
  shares details needs only `calendar.events`, so **full-detail lookups work before
  re-consent**. The missing scope matters only in the busy-only fallback.
- Detection: the provider returns `calendar.ErrScheduleScope` (new sentinel). It recognises the
  403 with `isOptionalServiceUnavailable`'s predicate, factored into a small
  `isInsufficientScope(err)` that both call. A dead token (401 / `invalid_grant`) goes through the
  existing `classifyAuthErr`, which wraps `calendar.ErrReauthRequired`. The IPC handler turns
  **both** into a normal result `{status: "reconnect", accountId}`, so the chip renders and the
  UI can offer the fix.
- UI: under the People chips, a one-line message "Reconnect <account> to see availability", with
  a `Reconnect` button that calls `DankCalService.reconnectAccount(account, cb)`. The account
  comes from `DankCalService.accounts` by `accountId`. On success, `PeopleService` refetches
  every person whose status is `reconnect`. The account list is refreshed by the existing
  `refreshAccounts()` in the completion callback (`DankCalService.qml:1510-1516`).
- Rejected alternatives:
  - (a) Persist the granted scopes in the token blob and check before calling. That changes the
    keyring format and still misses scopes unticked on the consent screen.
  - (b) Call Google's `tokeninfo` endpoint. That costs an extra network call on every lookup for
    no gain over the 403.
  - (c) Incremental auth (`include_granted_scopes`), requesting the scope only on a People
    reconnect. It adds a second flow type. Keep it in reserve in case upstream objects to the
    new scope on every login (see Risks).

## 2. Daemon

### 2.1 Where the fetch lives

Options:

| | Where | For | Against |
|---|---|---|---|
| A | Method on the Google `Provider`, exposed through a new **optional** interface `calendar.ScheduleReader` (like `Responder`, `Importer`, `NoticeReporter` in `core/internal/calendar/provider.go:52-80`) | Reuses the token source and persisting refresh (`oauthbase.LoadTokenSource`), the per-account quota gate shared with sync (`googleCall`, `quota.go:157`), `fromGoogleEvent`, `classifyAuthErr`, and the existing httptest pattern. The IPC handler stays provider-agnostic: Microsoft could implement it later with no IPC change. | One more optional interface. |
| B | New package `internal/people` building its own `calendar.Service` | Self-contained | Duplicates token loading, quota and error classification. It bypasses the quota gate, so lookups and sync could together exceed Google's per-user rate. It adds a new `Deps` field. |
| C | Google calls inline in `internal/ipc` | Fewest files | Puts provider internals in the API layer, and upstream would push back. |

**Recommend A.** The optional interface costs about 25 lines and is the pattern upstream
already uses for provider-specific abilities. Orchestration (account choice, owner matching,
JSON shape) goes in a new `core/internal/ipc/people.go`, the way `events_write.go` orchestrates
provider writes. It needs no new `Deps` field (it uses `Repo`, `Registry` and `Secrets`) and no
new package.

New file `core/internal/calendar/schedule.go`:

```go
// ScheduleReader is implemented by providers that can read another person's calendar
// (details where shared, otherwise free/busy). Results are never stored.
type ScheduleReader interface {
	ReadSchedule(ctx context.Context, email string, from, to time.Time) (*Schedule, error)
}

type ScheduleAccess string

const (
	ScheduleDetails     ScheduleAccess = "details"
	ScheduleBusy        ScheduleAccess = "busy"
	ScheduleUnavailable ScheduleAccess = "unavailable"
)

type Schedule struct {
	Access ScheduleAccess
	Name   string          // display name when a source reveals it, else ""
	Events []ScheduleEvent // Access == ScheduleDetails
	Busy   []TimeSpan      // Access == ScheduleBusy
}

// ScheduleEvent is a read-only occurrence. Event.UID/RecurringID/OriginalStart carry the
// provider's occurrence identity; ICalUID is the cross-calendar RFC 5545 UID.
type ScheduleEvent struct {
	Event
	ICalUID string
}

type TimeSpan struct{ Start, End time.Time }

// ErrScheduleScope: the account's token lacks the permission to read availability.
var ErrScheduleScope = errors.New("availability permission not granted")
```

### 2.2 Google implementation: `core/internal/providers/google/schedule.go` (new)

`func (p *Provider) ReadSchedule(ctx, email, from, to)`:

1. **`events.list(email)`**:
   `TimeMin/TimeMax`, `SingleEvents(true)`, `ShowDeleted(false)`, `MaxResults(maxPageSize)`,
   `EventTypes("default", "focusTime", "outOfOffice")`, which drops `workingLocation` and
   `birthday` noise. Also a `Fields(...)` partial response limited to
   `accessRole,summary,nextPageToken,items(id,iCalUID,recurringEventId,originalStartTime,start,end,summary,location,status,visibility,attendees(email,displayName,responseStatus))`.
   That is data minimisation: no descriptions, links or conference data reach the daemon.
   Follow `nextPageToken`, and go through `googleCall(ctx, p, true, …)` so the quota gate and
   read retries apply.
   - 200 and `AccessRole` in {reader, writerWithoutPrivateAccess, writer, owner} → `ScheduleDetails`.
     Map each item with `fromGoogleEvent(cal.Calendar{}, item)` plus `ICalUID`. Drop
     `status == cancelled` and items where the colleague's own attendee entry says
     `declined` (they are free then). An item with no summary (a private event under reader
     access) stays in the list, and the UI draws it as busy. `Name` is the `DisplayName` of the
     attendee whose email equals `email`, if any.
   - 200 and `AccessRole` `freeBusyReader`/`none` → step 2. Keep the item start/end times as
     `spans` in case step 2 hits the scope error.
   - `googleapi.Error` 404 or 403 (not rate-limit, not insufficient-scope) or 400 → step 2 with
     no spans.
   - 401 or `invalid_grant` → `classifyAuthErr(err)` (wraps `ErrReauthRequired`).
   - Anything else (network, exhausted quota retries) → return the error.
2. **`freebusy.query`** with `Items: [{Id: email}]` and the same range (a single calendar, far
   below the 50-per-request limit):
   - `Calendars[email].Errors` non-empty (`notFound`, `groupTooBig`, …) → `ScheduleUnavailable`.
   - otherwise → `ScheduleBusy` with `Busy` spans.
   - 403 insufficient scope → if step 1 left `spans`, return `ScheduleBusy` from them, which
     degrades gracefully before re-consent. Otherwise return `ErrScheduleScope`.
   - 401 or `invalid_grant` → `classifyAuthErr`.

**"unavailable/notFound" detection** therefore comes from the freebusy per-calendar `errors`
array, never from the events.list 404 alone: a 404 there only means "no read access".

`ReadSchedule` logs nothing. The Google errors it returns contain the colleague's address in
the URL but no event data.

### 2.3 IPC: `people.schedule` (recipe A)

- `core/internal/ipc/registry.go` (after the `ui` group near `:92`): add
  `{Name: "people.schedule", Group: "people", Desc: "Read a colleague's schedule for a range (not stored)", Params: []ParamSpec{req("email", ""), req("from", "RFC3339"), req("to", "RFC3339"), opt("accountId", "defaults to a domain match, else the first Google account")}}`.
- `core/internal/ipc/router.go:33`: add `case strings.HasPrefix(req.Method, "people."): HandlePeople(...)`.
- `core/internal/ipc/server.go:19`: add `"people"` to `Capabilities`.
- `core/internal/ipc/people.go` (new): `HandlePeople` switch and `handlePeopleSchedule`.
  - Validate: `email` must be non-empty and contain one `@` (lower-cased and trimmed). `from`
    and `to` must parse as RFC3339 with `to` after `from` and `to - from` at most 62 days.
    `RespondError` and return early on each failure.
  - **Account choice** is the pure function `pickScheduleAccount(accounts []*ent.Account,
    email, override string) (*ent.Account, error)`:
    - Use Google accounts only, in `ListAccounts` order (`created_at` ascending,
      `core/repo/accounts_queries.go:24`).
    - `override` must name one of them.
    - Otherwise take the first whose id's domain (the id is the lower-cased email,
      `add.go:217`) equals the email's domain, else the first Google account.
    - With no Google account, return an error (`RespondError "no Google account connected"`).
    - Accounts with `NeedsReauth` are still chosen. The provider then fails with
      `ErrReauthRequired` → `reconnect`, which is the right message.
  - Build the provider with `deps.Registry.Build(ctx, domAcc, deps.Secrets)`, the same way as
    `providerForCalendar` (`events_write.go:419-452`). Close it with `defer provider.Close()`.
    Type-assert `calendar.ScheduleReader`, otherwise `RespondError`.
  - Map `errors.Is(err, calendar.ErrScheduleScope) || errors.Is(err, calendar.ErrReauthRequired)`
    to the result `{status: "reconnect"}`. Other errors → `RespondError(err.Error())`.
  - **Owner match** (details only; see section 4) using `deps.Repo.ListCalendars` and
    `deps.Repo.ListEvents(IncludeRecurring, From, To)`.
- Result (`Respond(w, req.ID, map[string]any{…})`):

```json
{
  "email": "alice@acme.com", "accountId": "me@acme.com",
  "status": "details | busy | unavailable | reconnect",
  "name": "Alice Doe",
  "events": [{"key": "<iCalUID>|<originalStart RFC3339>", "summary": "...", "location": "...",
              "start": "...", "end": "...", "allDay": false, "status": "confirmed",
              "private": false,
              "ownEventId": "...", "ownUid": "...", "ownStart": "..."}],
  "busy": [{"start": "...", "end": "..."}]
}
```

  `events` and `busy` are always arrays. `own*` is present only when the event matches one of
  the owner's occurrences.
- **No bus publish:** nothing changed in the daemon. **No cache:** each lookup is one or two
  Google reads through the per-account quota gate. The UI asks once per person per 7-week
  window (3.5), so a cache would buy almost nothing and would hold colleague details in memory
  after the chip is gone. **Nothing persisted:** the handler never touches the repo for
  writes. **Nothing logged:** the handler has no `log.*` call. The provider's token refresh may
  rewrite the keyring token, as a normal sync does; that is not `dankcal.db` or `ui-settings.json`.
- Doc hook: editing `registry.go`/`router.go` triggers `check-docs.py` REVIEW_RULES for
  `dcal-recipes` (`.claude/tools/check-docs.py:87`). In recipe A step 2, add `people.go` to the
  list of handler files, and stage it with the commit.

## 3. QML

### 3.1 State: a new singleton `quickshell/Services/PeopleService.qml`

**Recommend a new singleton over growing `DankCalService`.** DankCalService is already over
1,500 lines and owns the daemon connection. People state is transient UI state with its own
lifecycle, and a singleton keeps the overlay out of `eventsForRange`, which section 0 shows must
not change. It talks to the daemon only through `DankCalService.sendRequest`, the same way
`FilesService` sits next to it.

- `property var people: []`. Each entry is `{email, name, color, status, accountId, events,
  busy, error, seq}`, where `status` is one of `loading | details | busy | unavailable |
  reconnect | error`.
- `readonly property bool active: people.length > 0`, used for fading.
  `readonly property var lanes: people.filter(p => p.status === "details" || p.status === "busy")`
  is used by the Day-view columns.
- `property int version`, bumped on every change. Views read it the way they read their
  `eventsVersion` (e.g. `DayView.qml:16,66-71`).
- `function add(email)`:
  - Trim and lower-case, validate, dedupe.
  - Reject an address equal to one of `DankCalService.accounts[].id`. That would duplicate
    the owner's own events, so return an error string for the field's `supportingText`.
  - Assign a color and `_fetch`.
- `function remove(email)`, `function clear()`, `function retry(email)`.
- `function ingest(email, response)`: the body of the IPC callback. It normalises events with
  the same rules as own events: make `DankCalService._normalizeEvent` public as
  `normalizeEvent` (a rename at `DankCalService.qml:621`, updating its callers at `:608`, `:653` and `:808`). It also normalises `ownStart` with `allDay` handling
  so that the key for an owner match equals `EventUtils.eventKey(ownEvent)`
  (`quickshell/Common/EventUtils.js:6`).
- A stale-response guard: each `_fetch` stores `++seq` on the person, and `ingest` drops
  replies whose seq is old or whose person was removed.
- Logging: `readonly property var log: Log.scoped("PeopleService")`, used for status only,
  never event data.

### 3.2 Colors

Reuse `DankCalService.fallbackPalette` (`DankCalService.qml:44`, 8 colours). A new person gets
the first palette entry not used by another current person, cycling past 8. The colour stays
fixed while the chip exists. Colours are hex strings, so every Theme helper call goes through
`Theme.toColor()` (see the 2026-09-25 lesson; `Theme.qml:627`).

### 3.3 How views get the overlay: a parallel call, not a second source inside `eventsForRange`

`PeopleService.overlayForDay(day)` returns merged overlay items for Week and Month (4).
`PeopleService.personItemsForDay(email, day)` returns one person's unmerged items for the Day
lanes (5). `PeopleService.sharedWith(ev)` returns the colleague colours for an own event (4).

An overlay item is:

```
{overlay: true, kind: "event" | "busy", title, location, start, end, allDay, color, stripes: [colors], email}
```

Build a per-day index once per `version` (map `dayKey → items`) so views calling this per
column per render stay cheap.

### 3.4 Styling

- **Fading own events:** add `property bool dimmed: false` to
  `quickshell/Widgets/EventChipBackground.qml`, and set `opacity: dimmed ? Theme.overlayDimOpacity : 1`
  on the root, which also fades its text children. Add
  `readonly property real overlayDimOpacity: 0.35` to `Theme.qml` next to the `rsvp*` helpers
  (`:620-677`). Views set `dimmed: PeopleService.active && PeopleService.sharedWith(modelData).length === 0`.
  A shared meeting stays at full strength because it is the meeting everybody is in. The RSVP
  fill, border, hatch and strikeout logic is untouched, so #22 cannot regress; the chip is only
  multiplied by the opacity.
- **Detail events:** new `quickshell/Widgets/PersonEventChip.qml`.
  - A `Rectangle` in the person colour with the strong look, i.e. what
    `Theme.rsvpFillColor("", c)` / `rsvpTextColor("", c)` return, so it matches an accepted own
    event. A title and an optional location line follow the same size rules as the view it is
    in; the host view passes `compact`/`titleLines`.
  - Hover shows a `DankTooltipV2` with title, time and person.
  - No `EventMouseArea`: the chip cannot be clicked, dragged, selected or opened.
- **Busy blocks:** the same widget with `kind: "busy"`:
  - fill `Theme.withAlpha(Theme.toColor(color), 0.18)`
  - 1 px border in the person colour
  - a 3 px solid bar on the leading edge
  - label `I18n.tr("Busy", "…")` in `Theme.surfaceText`

  This is clearly different from the solid detail chip. It avoids `TentativeHatch`, which
  already means "tentative" on own events. A private detail event with no title uses the busy
  look.
- **Stripes:** new `quickshell/Widgets/AttendeeStripes.qml` (`property var colors`, a `Row` of
  3 px bars, or 2 px when `compact`, anchored to the trailing edge). It is used inside own
  chips (`colors: PeopleService.sharedWith(modelData)`) and inside merged `PersonEventChip`s.

### 3.5 Refetch on navigation

The visible range is already published: `CalendarWindow.onDisplayDateChanged` sets
`DankCalService.focusDate = displayDate` (`CalendarWindow.qml:424-428`), and DankCalService uses
it for its own window (`DankCalService.qml:40,577-588`). PeopleService listens with
`Connections { target: DankCalService; function onFocusDateChanged() }` and fetches the window
`[firstOfMonth(focusDate) − 7 d, firstOfMonth(focusDate) + 42 d)`. That covers:

- every Month grid (starts ≥ 6 days before the 1st, spans 42 days)
- the Week view's 9 rendered columns (`WeekView.qml:680`, `dayAt(-1..7)`)
- the Day view

It refetches every person only when the `YYYY-MM` of `focusDate` changes, behind a 250 ms
debounce `Timer` so paging with PageUp does not fire a request per step. Nothing polls.
Reconnect success and `retry(email)` also refetch.

### 3.6 Sidebar, chips, `x`, Esc

`quickshell/Modules/CalendarSidebar.qml`: a new first block in `scrollColumn` (`:544`),
above "My calendars".

- `SectionHeader` titled `I18n.tr("People", …)`, not collapsible, for simplicity.
- `DankSearchField` (`quickshell/DankCommon/Widgets/DankSearchField.qml`, used as in
  `Modals/SearchModal.qml:295-305`) with placeholder "Search for people" and `leftIconName: "person_search"`.
  - `onAccepted`: `PeopleService.add(text)`. On success clear the text and keep focus for the
    next address; on an error show it via `supportingText`/`isError`.
  - `Keys.onReturnPressed`/`onEnterPressed` accept the event, as SearchModal does, so it
    doesn't reach the window's Enter handler.
  - `Keys.onEscapePressed`: `PeopleService.clear()`, clear the text, `event.accepted = true`,
    and emit a new sidebar signal `peopleSearchDismissed`. CalendarWindow
    (`CalendarWindow.qml:729-750`) handles it with `focusScope.forceActiveFocus()`. Without
    accepting it, Esc propagates to the window's handler (`CalendarWindow.qml:528`) and can
    close the window.
- Chips in a `Flow` under the field, as a new `quickshell/Widgets/PersonChip.qml`:
  - `StyledRect`, colour dot, `name || email` (elided), full email in the tooltip
  - status: a `DankSpinner` while loading; for `unavailable` a `block` icon and the text
    "Unavailable" with the dot greyed; for `error` a `warning` icon, where clicking the chip
    retries; for `reconnect` a `sync_problem` icon
  - `DankIconButton { iconName: "close" }` → `PeopleService.remove(email)`
  - Removing the last chip makes `active` false, so everything returns to full opacity by
    binding.
- Below the chips, when any person is `reconnect`: a `StyledText` "Reconnect %1 to see
  availability" plus `DankButton` "Reconnect" (reuse the existing "Reconnect" term), which calls
  `DankCalService.reconnectAccount(...)` (3.1).
- If `DankCalService.accounts` has no Google account, the field is disabled with the
  supporting text "Connect a Google account to look up people".
- Run `make i18n-extract` after adding the strings. `translations/en.json` is generated and
  never edited by hand.

Agenda view and `MonthDayPopover` show no overlay and no fading. The spec names Week, Day and
Month. The popover keeps listing own events only; the month cell's "+N more" counts own and
overlay items. This is a known limitation, listed in the PR.

## 4. Merging shared meetings

**Where: identity in the daemon, grouping in QML.**

- **Owner ↔ colleague match (daemon, `people.go`).** Owner rows do not store an iCalUID (0), so
  matching on iCalUID against them is impossible without a schema change. Match instead on the
  occurrence identity both sides do store, the RFC 5545 pair UID + RECURRENCE-ID:
  - `own.UID == theirs.UID` covers single events and owner exception rows, where both carry the
    Google instance id.
  - `own.UID == theirs.RecurringID && own.Start.Equal(theirs.OriginalStart)` covers owner
    occurrences expanded from a master, including the master row itself.

  This works because Google gives every attendee's copy of a Google-organised event the same
  event id. `fromGoogleEvent` already fills `RecurringID` and `OriginalStart` for colleague
  instances. Only owner occurrences in **visible Google calendars** are candidates (hidden
  calendars are excluded, so a colleague copy is not suppressed behind an owner event that is
  never drawn). Index the owner occurrences by `UID` and by `UID|Start` for O(n) matching. On a
  match, set `ownEventId`, `ownUid` and `ownStart`.
- **Colleague ↔ colleague match (QML).** Each detail event carries
  `key = iCalUID + "|" + (originalStart || start)`. That is the real iCalUID, available live
  for colleagues, so this also merges events organised outside Google.
- **Drawing (`PeopleService._buildIndex`):**
  1. A detail event with an `own*` match is not drawn as an overlay item. Instead
     `sharedWith[EventUtils.eventKey(own)]` gets the person's colour. The own chip draws at full
     opacity with one stripe per colleague; the owner is the chip itself.
  2. Remaining detail events are grouped by `key`. The group becomes one item in the colour of
     the first person in chip order, with `stripes` holding every looked-up person who has it.
  3. Busy spans are never merged: they carry no id, as the issue's Risks note.
- Known degradation, to verify live: an event organised outside Google that the owner also
  has may carry a different Google `id` in the owner's calendar. It then is not merged with
  the owner's chip and draws side by side. Colleague ↔ colleague still merges through iCalUID.

## 5. Day view: one column per person

`quickshell/Modules/views/DayView.qml` lays out the timed area as one `Item`
(`:303-306`), with chips at `x: 8 + column*(laneWidth+gap)` from `layoutTimedEvents`
(`:364-384`). Change:

- `readonly property var laneOwners: PeopleService.lanes.length > 0 ? [null].concat(PeopleService.lanes) : [null]`
  gives the owner first, then colleagues in chip order (`unavailable`/`reconnect`/`loading`
  people get no column).
  - `laneCount = laneOwners.length`
  - `laneWidth = (areaWidth - (laneCount-1)*gap) / laneCount`
  - `laneX(i) = i*(laneWidth+gap)`
- `timedEvents` becomes per lane. Lane 0 is today's computation, unchanged. Lane i ≥ 1 runs
  `PeopleService.personItemsForDay(email, displayDate)` through the same `EventUtils.timedSlot`
  and `DankCalService.layoutTimedEvents`, tagged with `lane: i`.
  - The existing own-chip delegate changes `x` to `laneX(0) + 8 + column*…`, with `usableWidth`
    taken from `laneWidth`.
  - A second `Repeater` draws `PersonEventChip`s at `laneX(modelData.lane) + …`.
  - Lanes are not merged: each column shows that person's own copy, so a shared meeting reads
    as a horizontal row across columns. Own chips still get stripes.
- A header row above `allDayStrip`, visible only when `laneCount > 1`: one cell per lane with
  the colour dot and name ("Me" for lane 0, from the existing term if there is one). There is a
  1 px `Theme.gridLine` separator between lanes, drawn in the timed area.
- `allDayStrip` uses the same lane geometry: a `Row` of per-lane `Column`s.
- `TimeGridCreateArea` stays full width. Drag-creating in a colleague's free slot creates an
  own event, which is the point of the feature.
- With no people, `laneCount == 1` and `laneX(0) == 0`, so the layout is identical to today.

## 6. Tests and verification

### 6.1 Go (no network, sandboxed)

- `core/internal/providers/google/schedule_test.go` (new), using the httptest + `WithEndpoint`
  pattern (`quota_test.go:96-135`). The server routes on `r.URL.Path`
  (`/calendars/{email}/events` vs `/freeBusy`). Each case builds
  `&Provider{account: cal.Account{ID: "me@acme.com"}, svc: svc, quota: q}`. Table cases:
  1. events.list 200 `accessRole: reader`, two pages → `ScheduleDetails`, events mapped,
     `ICalUID` set, the cancelled item and the colleague-declined item dropped, `Name` from the
     attendee entry. Assert freebusy was **not** called.
  2. 200 `freeBusyReader` → freebusy called → `ScheduleBusy` with spans.
  3. 404 → freebusy 200 → `ScheduleBusy`.
  4. 404 → freebusy `calendars[email].errors[{reason: notFound}]` → `ScheduleUnavailable`.
  5. 404 → freebusy 403 `insufficientPermissions` → `errors.Is(err, cal.ErrScheduleScope)`.
  6. 200 `freeBusyReader` with items → freebusy 403 insufficient scope → `ScheduleBusy` from
     the item spans.
  7. 401 → `errors.Is(err, cal.ErrReauthRequired)`.

  Assert the request query (`singleEvents=true`, `timeMin/timeMax`, `eventTypes`, `fields`)
  in case 1.
- `core/internal/ipc/people_test.go` (new):
  - Table test for `pickScheduleAccount`: domain match, fallback to the first, override,
    unknown override, no Google account, non-Google accounts ignored.
  - Route tests with `routeAndRead` and a memory repo seeded like `newIcsFixture`
    (`ics_test.go:30-48`) with Google accounts `me@acme.com` and `me@gmail.com`. The provider is
    `struct{ *mocks.MockProvider; *mocks.MockScheduleReader }`, returned by a
    `MockProviderFactory`. Cases:
    - missing email, bad range, `to` not after `from` → error
    - domain match builds the acme account (expecter on `Build` with the account id)
    - `ErrScheduleScope` and `ErrReauthRequired` → `status: reconnect` + `accountId`
    - provider without `ScheduleReader` → error
    - details with an owner match for a single event (`UID` equal) and a recurring series
      (owner master with RRULE, expanded; colleague `RecurringID` = master, `OriginalStart` =
      occurrence) → `ownEventId`/`ownStart` set
    - a match in a **hidden** calendar is not reported
- `core/.mockery.yml`: add `ScheduleReader: {}` under `internal/calendar`, then `make mocks`.
  This generates `core/internal/mocks/mock_schedule_reader.go`, which is never hand-written.

### 6.2 Proving scenarios 1–5 without network

The dev instance runs with `PrivateNetwork=yes`, loopback only (`.claude/tools/dev-instance.sh:27-31`).
A fake Google server outside the namespace is unreachable from it. Pointing the provider at
a fake endpoint would need a shipped endpoint-override hook. **No fixture mode or test-only
path goes into shipped code.** Instead:

1. **Offscreen QML harness** (scratchpad only, never committed), per the 2026-09-25 lessons:
   - `quickshell -p <scratch>/main.qml`, with `Common`, `Widgets`, `Services`, `Modules` and
     `DankCommon` symlinked from the checkout's `quickshell/`.
   - `QT_QPA_PLATFORM=offscreen`, and `HOME`/`XDG_*` pointed at the scratch dir. Record
     `sha256sum ~/.config/dankcal/*` before and after.
   - It sets `DankCalService.calendars`/`events` to fixture own events (including one meeting
     shared with both colleagues). It calls `PeopleService.add()` for three addresses; with no
     socket, `sendRequest` answers "not connected" at once (`DankCalService.qml:313-320`).
     It then calls `PeopleService.ingest(email, fixture)` with JSON in the exact IPC result
     shape: Alice `details` with a shared meeting carrying `own*`, Bob `busy`, and
     `nobody@acme.com` `unavailable`. `ingest` is the production callback body, not a test hook.
   - It instantiates `WeekView`, `MonthView` and `DayView` at a fixed size and grabs PNGs with
     `grabToImage`. That covers scenarios 1–4 and the chip states of 5. `remove()`/`clear()`
     then a regrab proves the rest of 5, and the Esc path is `peopleSearchDismissed` via the
     sidebar's handler function.
2. **Dev instance** (`verify-change` section 4) for regressions and the daemon path:
   - `dev-instance.sh ipc describe` lists `people.schedule`.
   - `dev-instance.sh ipc people.schedule email=a@acme.com from=… to=…` returns the offline
     error, proving the route, account choice and provider build. A missing email returns the
     validation error.
   - With no people: Week/Month/Day screenshots are unchanged against `master`, and #22 RSVP
     chips are intact.
   - Typing an address in the sidebar shows the `error` chip state offline.
   - `sha256sum` of the dev copy's `dankcal.db` and `ui-settings.json` before and after lookups,
     plus `git status` showing no new file under `core/ent/migrate/migrations/`.
3. **Live Google (owner only):** the acceptance item "after re-consent a lookup succeeds
   against the real Google account" cannot be run offline. See open question 1.

## 7. Phases

Every phase ends with `make fmt && make vet && make test`, golangci-lint (CLAUDE.md "Known
quirks") and the phase's proof. QML phases also run `make i18n-extract` and the no-`console.*`
check.

**P1 — daemon (dcal-builder).** Acceptance: constraint (provider) Go tests; constraint (scope);
constraint (no migration).
- `core/internal/oauth/google.go` (scope)
- `core/internal/calendar/schedule.go` (new)
- `core/internal/providers/google/schedule.go` + `schedule_test.go` (new)
- `core/internal/providers/google/provider.go` (extract `isInsufficientScope`, no behaviour change)
- `core/internal/ipc/people.go` + `people_test.go` (new)
- `core/internal/ipc/registry.go`, `router.go`, `server.go`
- `core/.mockery.yml` + the generated mock
- `.claude/skills/dcal-recipes/SKILL.md` (handler file list)

Proof: test output, `dev-instance.sh ipc describe | grep people.schedule`, and the offline
`ipc people.schedule` error.

**P2 — PeopleService + sidebar (dcal-builder).** Acceptance: scenario 5 (chips, `x`, Esc,
unavailable chip), the Reconnect message.
- `quickshell/Services/PeopleService.qml` (new)
- `quickshell/Services/DankCalService.qml` (`normalizeEvent` public)
- `quickshell/Modules/CalendarSidebar.qml`, `quickshell/Modules/CalendarWindow.qml`
  (`peopleSearchDismissed` → refocus)
- `quickshell/Widgets/PersonChip.qml` (new)
- `translations/en.json` via `make i18n-extract`

Proof: harness PNGs of chips in every status, and the dev-instance offline chip.

**P3 — overlay in Week + Month, fading, busy blocks (dcal-builder).** Acceptance: scenario 1
(week + month) and scenario 2.
- `quickshell/Widgets/EventChipBackground.qml` (`dimmed`)
- `quickshell/Common/Theme.qml` (`overlayDimOpacity`)
- `quickshell/Widgets/PersonEventChip.qml` (new)
- `PeopleService.overlayForDay` (without merging yet: every detail event is its own item)
- `quickshell/Modules/views/WeekView.qml`:
  - `timedEventsFor` (`:237-250`) lays out own and overlay slots together through
    `layoutTimedEvents`, so colleague chips sit **beside** own chips in the overlap columns
    rather than on top of them (open question 3)
  - the day column (`:680-760`) splits the model into the existing own `Repeater` and a new
    overlay `Repeater`
  - the all-day strip (`:458-500`, `allDayMax` `:256-262`) gets overlay all-day chips after
    own ones
- `quickshell/Modules/views/MonthView.qml`: the cell (`:312-340`, `:450-460`, `:537`) gets a
  second `Repeater` for overlay chips.
  - While `active`, overlay chips take the first slots, then own chips fill the rest.
  - `+N more` counts both.

Proof: harness PNGs for week and month, plus a no-people regression screenshot on the dev
instance.

**P4 — merging + Day-view columns (dcal-builder).** Acceptance: scenarios 3 and 4.
- `PeopleService` (`_buildIndex` merge, `sharedWith`, `personItemsForDay`)
- `quickshell/Widgets/AttendeeStripes.qml` (new)
- Week/Month own delegates (`dimmed` exception + stripes)
- `quickshell/Modules/views/DayView.qml` (lanes, header, all-day lanes)

Proof: harness PNGs for the shared meeting in week view and 3 lanes in day view.

**P5 — verify, review, fix** (dcal-verifier, then dcal-reviewer, then fixes), as in `todo.md`.
The live Google acceptance follows open question 1.

## 8. Risks and scope flags for the owner

- **No migration, no schema change, no `Deps` change.** The new surface is one optional
  provider interface, one IPC group, one QML singleton and four widgets.
- **The OAuth scope affects upstream's built-in client.** Every login from the upstream binary
  would request `calendar.events.freebusy`. The built-in client's consent screen (Google Cloud
  project owned by AvengeMedia, `core/internal/oauth/googledefaults.go`) must list the scope,
  or users see an unverified-scope warning. That is a maintainer action, so say it in the
  upstream PR. The fallback is incremental auth (1c).
- **Workspace admin policy** may block third-party access to the scope or to other users'
  calendars. The chip then shows `unavailable`, which is correct but can surprise. Say so in
  the PR.
- **Unverified Google behaviours**, to check in the live test:
  - whether events.list on a free/busy-only colleague returns 200 `freeBusyReader` with item
    times, or a 404 (both are handled)
  - that attendee copies share the event id (the owner merge relies on it)
  - that a 49-day `freebusy.query` range is accepted; if not, split into two queries in P1's
    fix round
- **Week density:** with three people, a 1/7-width day column split into overlap columns gets
  narrow. It is acceptable, and Day view is the remedy.

## 9. Open questions for the owner

1. **Live acceptance path.** The "Reconnect, then a real lookup succeeds" item needs network
   and the real account. Should the owner run the branch with `make run` (stop `dcal.service`
   first; it uses the real data and rewrites the Google token on reconnect), or check it after
   merge and deploy?
2. **The scope on every login vs incremental auth** (8, second bullet): keep the spec's "add to
   `GoogleScopes()`" (recommended, simplest), or request it only from the People reconnect?
3. **Week layout:** colleague chips side by side with the owner's faded chips (recommended:
   nothing is hidden and own chips stay clickable), or drawn over them with the owner's chips
   translucent behind?
