# Dank Calendar — personal fork

Fork of `AvengeMedia/dankcalendar`: this machine's daily driver and a base for features that may
go upstream as PRs, so all code follows `CONTRIBUTING.md` (read it before a first change).

- `origin` = `valicaa/dankcalendar` (branches + PRs), `upstream` = `AvengeMedia/dankcalendar`.
- Installed build: `~/.local/bin/dcal`, run by `~/.config/systemd/user/dcal.service`
  (no AUR package, no autostart entry — never re-enable the in-app "Start at login").
- User data: `~/.local/share/dankcal/` (SQLite `dankcal.db` + keyring), UI settings:
  `~/.config/dankcal/ui-settings.json`. Treat both as production data.

## Working mode — the main session is the project manager

The main session follows `project-manager`: it elicits, specs (a GitHub issue), delegates to
`.claude/agents/`, and accepts only evidence. Subagents skip this, working their brief directly.

## Skills — use them, every feature goes through the same path

| Skill | When |
|---|---|
| `project-manager` | Every user request: elicit → spec → delegate to `.claude/agents/` → verify evidence → report. |
| `new-feature` | Starting any feature or behaviour change. Drives spec → branch → build → verify → PR → deploy. |
| `dcal-recipes` | Implementing: adding an IPC method, UI setting, settings page, HTTP endpoint, DB migration, QML view. |
| `verify-change` | Before claiming anything works or committing. |
| `deploy-local` | Putting a build onto the running desktop calendar. |
| `sync-upstream` | Pulling new commits from AvengeMedia into the fork. |
| `upstream-pr` | Turning a finished feature into a clean PR against AvengeMedia. |
| `code-graph` | Before reading source to trace call chains, callers, blast radius (`.claude/tools/graph-calls.py <path>`); refreshing the graph. Overrides the global graphify skill's "run `graphify query` first" default here. |

## Branch model

- **Issue-first:** every change except `project-manager` step 0's trivial ones starts as an
  issue on `valicaa/dankcalendar` (body = spec, template: `project-manager` step 2), then a branch.
- `master` = `upstream/master` + fork tooling (this file, `.claude/`, `tasks/`,
  `.graphifyignore`) and finished features; the only branch deployed. It moves only when the
  owner merges a PR on GitHub — that merge is the OK to deploy, never asked in chat.
- `feat|fix|chore/<N>-<slug>` branches off `master` via `gh issue develop N -R
  valicaa/dankcalendar --name <prefix>/<N>-<slug> --base master --checkout` (every `gh` command
  carries `-R`, never `gh repo set-default`) and ends as a PR (`Closes #N` in its body only),
  the checkout back on `master`. Other PR branches: `docs/<slug>` (step 0), `sync/upstream-<hash>`.
- `pr/<slug>` is created by the `upstream-pr` skill off `upstream/master`, code commits only —
  never `CLAUDE.md`, `.claude/`, `tasks/`, `.graphifyignore` or a fork `#N`.
- One feature is worked at a time (its branch checked out) until `new-feature` 6.2 opens its PR;
  writing agents take turns there (never `isolation: worktree`); the PM commits all of `tasks/`.

## Architecture — two halves, one binary

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
# hot-reload UI work, from core/ with the service stopped:
DCAL_ENABLE_HOTRELOAD=1 go run ./cmd/dcal run -c ../quickshell
```

## Lessons and keeping these docs current

- `tasks/lessons.md` is injected at session start by a hook. When the user corrects you, or you
  catch your own mistake, add a dated rule there in the same session.
- This file holds facts and rules only, within 120 lines. A procedure of more than a few steps
  belongs in a skill under `.claude/skills/`, with a row in the table above.
- A PreToolUse hook runs `.claude/tools/check-docs.py` on every commit: it blocks on broken doc
  references, the line budget, bad frontmatter, roster drift, commits off the branch model, and
  undocumented doc-relevant code changes — stage the listed docs, or `check-docs.py --ack`.

## Rules

- `CGO_ENABLED=0` must always build — no cgo dependencies.
- Never edit generated code: `core/ent/*` (except `schema/`, `generate.go`, `migrate/`),
  `core/internal/mocks/` (mockery: `.mockery.yml` + `make mocks`, never hand-written),
  `core/internal/shellembed/dist/`, `quickshell/translations/en.json`.
- Go: early returns, `switch` over if/else chains, `any` not `interface{}`, sparse comments that
  explain constraints rather than narrate; tests: testify, sandboxed (no network/system
  services), `repo.OpenMemory`, `t.TempDir()`, `humatest`, table-driven for pure functions.
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

- `make dev`/untagged builds lack embedded UI (run with `-c ../quickshell`); only one dcal
  instance runs per session — a second exits with "already running".
- `internal/ipc` handlers name their request `req`, shadowing the `req()` ParamSpec helper.
- Comment in `core/internal/settings/settings.go` points at
  `quickshell/Services/SettingsData.qml`; the real file is `quickshell/Common/SettingsData.qml`.
- `golangci-lint` (CI uses v2.11) isn't installed locally; from `core/`, run
  `GOTOOLCHAIN=go1.26.4 go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.11.0 run`
  (pin matches `go.mod` — system Go 1.27 breaks lint v2.11).
