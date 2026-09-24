---
name: code-graph
description: Use before reading Dank Calendar source to find a call chain, who calls a function, the blast radius of a change, which Go handler serves a QML IPC call, or where something lives — and when refreshing the graph after Go or QML changes. Cheaper than reading whole files.
---

# Code graph (graphify)

`graphify-out/graph.json` maps hand-written code, about 3k nodes. `.graphifyignore` drops
generated Ent code, mocks, the submodule, translations and assets. The graph is local only,
via `.git/info/exclude`. Go comes from the AST; QML comes from LLM subagents, because graphify
has no QML parser (Graphify-Labs/graphify#1716). Find the chain here, then read only the lines it
cites. This skill overrides the global graphify skill's "run `graphify query` first" default.

**Linked worktrees.** `graphify-out/` is excluded from git, so it only exists in the checkout
that built it — normally the main checkout. `graph-calls.py` and `graph-qml.py` resolve it as:
this checkout's `graphify-out/` if present, else the main checkout's, found via `git
rev-parse --path-format=absolute --git-common-dir` (its parent dir). Running these tools from a
linked worktree therefore transparently uses the main checkout's graph — same command, same
output. That graph reflects the main checkout's branch (normally `master`), not the worktree's,
so it can be stale for anything the worktree's branch changed; treat call chains it shows for
those files as a starting point to verify against source, not ground truth. If no graph exists
in either place, the tools point at this "Keeping QML current" section rather than a bare full
rebuild.

```bash
.claude/tools/graph-calls.py core/internal/sync/                 # call map + node ids + grep gap-fill
.claude/tools/graph-calls.py quickshell/Services/DankCalService.qml --grep events.delete  # -> Go handler
G=~/.local/share/graphify-venv/bin/graphify
$G explain <node-id>                                             # one node + neighbours (~1KB)
$G affected <node-id> --relation calls --depth 3                 # callers, transitively
$G query "<exact symbols>" --context call --budget 800           # call edges only, file:Lnn each
GRAPHIFY_VIZ_NODE_LIMIT=0 $G update .                            # refresh Go, skip graph.html (~10s, no LLM)
.claude/tools/graph-qml.py status                                # which QML changed (no LLM)
```

- **Start with `graph-calls.py`.** It is scoped by path, so same-named methods (`Wake`,
  `HandleAction`, `save`) can't resolve to the wrong package. It prints the node ids that
  `explain`/`affected` need. `query` matches words fuzzily and often starts from the wrong
  same-named node, so use it only with `--context call`. Don't use `graphify path`: it
  resolves even exact ids to the wrong node. Ignore any hint to run `graphify extract --force`:
  it would drop the QML nodes.
- **Missing edges — the call exists but the graph has no edge:**
  - Go calls through a struct field or an interface (`e.repo.X`, `deps.Repo.X`,
    `provider.CreateEvent`) are not resolved.
    - They are missing from `->`, and the method gets no callers. None of the 59 `Repo`
      methods has a graph caller outside `core/repo`, so `affected` on them returns nothing.
    - `graph-calls.py` prints `~ name matches` for such methods. That's a grep on `.Name(`, so
      check the receiver: `.Start()` also matches other engines.
  - QML → daemon IPC method strings (`ipc_method_*` nodes). `graph-calls.py` prints the Go
    `case` and the `handle…()` function it calls, or `(inline in case)` when the `case` body
    handles the method itself instead of calling a `handle…()` function.
  - Not resolved anywhere, so grep for them:
    - implementations of an interface method: `git grep -n 'func (p \*Provider) Sync(' core/internal/providers`
    - anonymous callbacks (`notifier.SetHandlers` in `daemon.go` → the engines' `HandleAction`)
    - bus `Publish(topic)` → `_handleEvent` in `DankCalService.qml`
  - Repeated calls between the same two functions collapse into one edge.
- **Keeping QML current.** Neither `update` nor `/graphify --update` sees `.qml`, and a full
  `/graphify` rebuild drops the QML nodes. Use `.claude/tools/graph-qml.py`:
  1. `status` lists the changed QML files.
  2. `prompt N <files…>` gives the prompt for one general-purpose subagent per ~20 files.
  3. `merge` caches the chunks and merges all cached QML into the graph. `merge` also restores
     QML after a full rebuild.

  Stale QML nodes are fine for finding your way around, so refresh after large UI changes and
  ask first, because extraction costs LLM tokens. `merge` deliberately skips graphify's fuzzy
  duplicate merging, which folded `system.autostart.get` into `.set`.
- `/graphify --update` is only for changed docs (`*.md`, workflows); `.graphifyignore` keeps it
  off assets and generated code.
- **Saved traces.** Traces live in `graphify-out/memory/`: event save path, remote sync →
  views, and the reminders/invitations engines. Read these before tracing the same flow again.
  Save a new trace with `$G save-result --question … --answer … --type query --nodes <ids> --outcome useful`.
- Deliberately not used here:
  - graphify's always-on PreToolUse hooks: they nudge on every Grep/Read, and the graph is
    blind to the calls above.
  - `graphify hook install`: it adds a tracked `.gitattributes` line that would leak into
    upstream PRs.
  - The MCP server: it needs an extra install, and its tool schemas cost context in every session.
