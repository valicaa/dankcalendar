# Dank Calendar — personal fork

Fork of `AvengeMedia/dankcalendar`, used as the daily driver on this machine and as a
base for new features. Any feature may later be offered upstream as a PR, so all code
follows upstream's rules in `CONTRIBUTING.md` (read it before a first change).

- `origin` = `valicaa/dankcalendar` (push here), `upstream` = `AvengeMedia/dankcalendar`.
- Installed build: `~/.local/bin/dcal`, run by `~/.config/systemd/user/dcal.service`
  (no AUR package, no autostart entry — never re-enable the in-app "Start at login").
- User data: `~/.local/share/dankcal/` (SQLite `dankcal.db` + keyring), UI settings:
  `~/.config/dankcal/ui-settings.json`. Treat both as production data.

## Skills — use them, every feature goes through the same path

| Skill | When |
|---|---|
| `new-feature` | Starting any feature or behaviour change. Drives spec → branch → build → verify → merge → deploy. |
| `dcal-recipes` | Implementing: adding an IPC method, UI setting, settings page, HTTP endpoint, DB migration, QML view. |
| `verify-change` | Before claiming anything works or committing. |
| `deploy-local` | Putting a build onto the running desktop calendar. |
| `sync-upstream` | Pulling new commits from AvengeMedia into the fork. |
| `upstream-pr` | Turning a finished feature into a clean PR against AvengeMedia. |

## Branch model

- `master` = `upstream/master` + fork tooling (this file, `.claude/`, `tasks/`) + finished
  features. It is what gets deployed.
- `feat/<slug>` branches off `master`, one feature each, merged back with `--no-ff`.
- `pr/<slug>` branches off `upstream/master` and carries only a feature's code commits —
  never `CLAUDE.md`, `.claude/`, or `tasks/`. Created by the `upstream-pr` skill.
- Keep planning-doc edits (`tasks/`) in their own commits so feature commits cherry-pick
  cleanly onto upstream.

## Architecture

Two halves, one binary:

- **`core/`** — Go daemon (module `github.com/AvengeMedia/dankcalendar/core`).
  `cmd/dcal/` is the cobra CLI and composition root (`daemon.go` wires everything via
  `ipc.Deps`). `internal/ipc/` is the API the UI uses. `repo/` wraps Ent (`ent/schema/`
  is the only hand-written part of `ent/`). `internal/providers/*` implement calendar
  backends; `internal/{sync,reminders,invitations}` are background engines. `api/` is a
  huma HTTP API used by external clients and OAuth only — not by the UI.
- **`quickshell/`** — Quickshell/QML UI. `Services/DankCalService.qml` is the only client
  of the daemon (IPC socket, `sendRequest(method, params, cb)` + topic subscriptions).
  `Common/` holds singletons (`Theme`, `SettingsData`, `I18n`), `Modules/` the window and
  views, `Modals/` dialogs and settings pages, `Widgets/` app widgets.
- **`quickshell/DankCommon`** is a symlink into the `dank-qml-common` submodule (still
  AvengeMedia's repo). Do not edit it here; changes belong in that repo.

Data flow for a feature: QML → `DankCalService.sendRequest` → `internal/ipc` handler →
provider (writes) / `repo` (reads) → `deps.Bus.Publish(topic)` → UI refreshes via its
subscription. There is no separate service layer.

## Commands (repo root)

```bash
make build            # release build, UI embedded (runs sync-shell) -> core/bin/dcal
make test             # go test (CGO_ENABLED=0)
make fmt && make vet
make run              # dev build against ./quickshell (stop the service first)
make i18n-extract     # after adding/changing any I18n.tr() string
make generate         # after editing core/ent/schema
make migrate name=x   # new DB migration from schema diff
```

Hot-reload UI work (from `core/`, service stopped):
`DCAL_ENABLE_HOTRELOAD=1 go run ./cmd/dcal run -c ../quickshell`

## Rules

- `CGO_ENABLED=0` must always build — no cgo dependencies.
- Never edit generated code: `core/ent/*` (except `schema/`, `generate.go`, `migrate/`),
  `core/internal/mocks/`, `core/internal/shellembed/dist/`, `quickshell/translations/en.json`.
- Mocks come from mockery (`.mockery.yml` + `make mocks`), never hand-written.
- Go style: early returns, `switch` over if/else chains, `any` not `interface{}`, sparse
  comments that explain constraints rather than narrate.
- Go tests: testify, sandboxed (no network/system services), `repo.OpenMemory`,
  `t.TempDir()`, `humatest`, table-driven for pure functions.
- QML: every user-facing string is `I18n.tr("text", "translator context")`, reusing existing
  terms in `translations/en.json` where possible. No `console.*` — use
  `readonly property var log: Log.scoped("Name")`. Use DankCommon wrappers (`DankListView`,
  `DankFlickable`, `DankIcon`, `StyledText`, …) instead of raw Qt equivalents.
- UI settings the daemon also reads need matching defaults in `SettingsData.qml` and
  `core/internal/settings/settings.go`.
- A new DB migration is a one-way door for the user's real database — call it out and get
  explicit approval before adding one, and back up `~/.local/share/dankcal` before deploying it.
- Commit subjects follow upstream: `area: lowercase summary` (e.g. `events: free/busy on
  create`, `settings: …`, `ui: …`). No trailing period.
- Upstream requires disclosing meaningful AI assistance in PRs, and closes PRs that read like
  unreviewed output. Match the style of the file you are editing.

## Known quirks

- `make dev` / untagged builds have no embedded UI; run them with `-c ../quickshell`.
- Only one dcal instance per session; a second one exits with "already running".
- `internal/ipc` handlers name their request `req`, shadowing the `req()` ParamSpec helper.
- Comment in `core/internal/settings/settings.go` points at `quickshell/Services/SettingsData.qml`;
  the real file is `quickshell/Common/SettingsData.qml`.
- `golangci-lint` (CI uses v2.11) is not installed locally; run it via
  `GOTOOLCHAIN=go1.26.4 go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.11.0 run`
  from `core/`. The toolchain pin (match `go.mod`) is required: system Go 1.27 breaks lint v2.11.
