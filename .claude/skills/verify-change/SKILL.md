---
name: verify-change
description: Use before claiming a Dank Calendar change works, before committing a finished step, and before merging or opening a PR. Runs the same checks as upstream's pre-commit hooks and CI, then proves the feature works in the running app.
---

# Verify a change

Evidence before claims. Report each check with its actual result; if one is skipped, say
why.

## 0. Docs and tooling

Any change touching `.claude/`, `CLAUDE.md` or `tasks/`: `.claude/tools/check-docs.py` must
print `docs OK`.

**Docs-only test** (`new-feature` and `project-manager` use this same test). A change is
docs-only only if this prints nothing for its range — `master...HEAD` on the branch,
`<M>~1..<M>` for a PR's merge commit `<M>`:

```bash
git diff --name-only master...HEAD | grep -vE '^(\.claude/|tasks/|CLAUDE\.md$|\.graphifyignore$|[^/]+\.md$)'
```

Any path it prints — code, the `dank-qml-common` submodule, `Makefile`, `scripts/`, `assets/`,
`flake.nix`, `distro/`, `.github/` — means the full checks in sections 1–5. A docs-only change
stops here, with no build, dev instance or service stop:

```bash
.claude/tools/check-docs.py
git diff --check master...HEAD
git diff master...HEAD
```

The last one is for reading: each changed command and path must match what it describes.

## 1. Static checks (mirror upstream pre-commit + CI)

From the repo root. In an `upstream-pr` worktree, follow `upstream-pr` step 2 instead of the
paths and base below.

```bash
cd core && go mod tidy && git diff --exit-code go.mod go.sum; cd ..
test -z "$(cd core && gofmt -s -l $(git ls-files '*.go' | grep -v '^ent/'))" || echo "gofmt needed"
make vet
make test
(cd core && GOTOOLCHAIN=go1.26.4 go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.11.0 run)  # pin toolchain: system Go 1.27 export data breaks lint v2.11
git diff master...HEAD -- 'quickshell/*.qml' | grep -n '^+.*console\.' && echo "console.* in QML — use Log.scoped"
git diff --check master...HEAD
```

Skip the Go checks only if the branch touches nothing under `core/`.

**Blast radius.** Refresh the graph first
(`GRAPHIFY_VIZ_NODE_LIMIT=0 ~/.local/share/graphify-venv/bin/graphify update .`, ~10s). For
each changed file, run `.claude/tools/graph-calls.py <file>`. Its `<-` and `~ call sites` lines
are the direct callers; for transitive callers of a key function add
`graphify affected <node-id> --relation calls --depth 3`. Every caller must be covered by a
test or by the manual checks in section 4. Changes to a `calendar.Provider` method need a grep
of every implementation (`git grep -n 'func (p \*Provider) <Method>(' core/internal/providers`),
because the graph doesn't resolve interface calls. Refreshing with `update` covers only Go. For
changed QML, the graph's QML callers are stale until the QML refresh runs, so grep QML callers
(`git grep -n '<function>(' quickshell`).

## 2. QML checks (when `quickshell/` changed)

- `qmllint` on changed files (`/usr/bin/qmllint quickshell/<file>.qml`). Treat new warnings
  on lines you touched as failures; pre-existing noise is fine — say so.
- `make i18n-extract` then `git status quickshell/translations` — must be clean (i.e. the
  extracted catalog was already committed). Every new visible string must be in `I18n.tr`.
- No raw `Flickable`/`ListView`/`ScrollView` added where a DankCommon wrapper exists.

## 3. Build

```bash
make build && core/bin/dcal version
```

## 4. See it working

Static checks do not prove UI behaviour. Use a **dev instance**, never `deploy-local` — that
installs onto the user's real desktop calendar and only ever deploys `master`, after the owner
merged the PR (`new-feature` 6.4, or `sync-upstream`). An unmerged branch is tried here, never
deployed.

`.claude/tools/dev-instance.sh` runs the branch's build **offline on a scratch copy of the real
data**, as the transient user unit `dankcal-dev`. It stops `dcal.service` for the run (the owner
approved this) and starts it again whenever `dankcal-dev` stops — `stop`, a crash, or the 2h
limit. Each block is one Bash call from any directory. `<checkout>` is the literal absolute
path of the checkout under test: the main checkout, or a linked worktree after
`git -C <checkout> submodule update --init`.

```bash
/home/nozomi/Documents/code/calendar/.claude/tools/dev-instance.sh start <checkout>
/home/nozomi/Documents/code/calendar/.claude/tools/dev-instance.sh probe
```

`start` builds `<checkout>/core` (a failed build leaves the live calendar alone), stops
`dcal.service`, copies `~/.local/share/dankcal`, `~/.config/dankcal` and
`~/.local/state/dankcal` under `/tmp/claude-1000/dankcal-dev/home` (the real files are only
read; `sqlite3` opens only the copies), and runs the build with `-c <checkout>/quickshell`
and `PrivateNetwork=yes`: loopback is its only interface, and it refuses to start otherwise.
Accounts keep their tokens, so they sync as offline (`network is unreachable` in the log).
`probe` must end with `offline: no remote host reachable from the dev instance`.

Then:
1. Show the window, navigate to the feature, and capture with
   `grim <scratchpad>/verify-<slug>.png`; Read the image and confirm what you expected is
   visible. For backend-only changes, exercise it with `ipc <method> key=value` and show the
   output. `status` prints the dev DB copy's goose and user version. Never use plain
   `dcal show` or `dcal ipc` here: with no dev instance up they reach, or cold-start, a daemon
   on the real data.
   ```bash
   /home/nozomi/Documents/code/calendar/.claude/tools/dev-instance.sh ipc ui.show
   /home/nozomi/Documents/code/calendar/.claude/tools/dev-instance.sh status
   ```
2. Check this run's logs for new errors:
   `journalctl --user -u dankcal-dev -I --no-pager | grep -E 'WARN|ERROR'` (dcal logs at
   journal priority info, so `-p warning` shows nothing). The per-account
   `sync error … network is unreachable` lines and `secret service unavailable` are expected.
3. Exercise edge cases from the issue's Scenarios and Acceptance (empty state, offline account,
   all-day events, 24h vs 12h clock, long titles). Don't sign in, re-authenticate or open links
   in the dev instance: the desktop portal hands them to the browser outside its namespace.
4. Always finish with the block below, and put its output in the report. It must end with
   `dev instance stopped cleanly` (exit 0): the real DB's sha256 is unchanged across the time
   `dcal.service` was stopped, no process runs the dev build or `<checkout>/quickshell`,
   `dankcal-dev` is inactive and `dcal` active. A `FAIL` line is a failed check; if `dcal` runs
   `<checkout>/quickshell`, `systemctl --user restart dcal` puts it back on its own UI.

```bash
/home/nozomi/Documents/code/calendar/.claude/tools/dev-instance.sh stop
```

## 5. Report

Summarise as a checklist: each check, pass/fail, and the evidence (command output excerpt
or screenshot). Anything that failed or was skipped is stated plainly.
