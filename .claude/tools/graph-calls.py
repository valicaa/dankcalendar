#!/usr/bin/env python3
"""Compact call map from graphify-out/graph.json for every function under a path prefix.

Usage: .claude/tools/graph-calls.py <source-path-prefix> [--grep WORD] [--tests]

  .claude/tools/graph-calls.py core/internal/sync/
  .claude/tools/graph-calls.py core/repo/ --grep getcalendar
  .claude/tools/graph-calls.py quickshell/Services/DankCalService.qml --grep events.delete

Per function: node id in [brackets] (for graphify explain/affected), "-> callee@line" and
"<- caller(file)". Two graph blind spots are filled from source:
  ~ name matches   Go methods with no graph caller outside their own file (typically called
                   through a struct field: e.repo.X, deps.Repo.X). git grep on ".Name(":
                   matches by name only, so check the receiver.
  ~ handler        QML IPC method strings ("events.create"): the `case` in core/internal/ipc
                   and the handler function it calls.
"->" lists only calls the AST resolved: calls through struct fields and interfaces
(deps.Repo.X, provider.CreateEvent) are missing there. Test files are skipped unless --tests.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]


def find_graphify_out():
    """graphify-out/ lives only in the checkout that built it (excluded via .git/info/exclude,
    so a linked worktree never has its own). Prefer this checkout's; otherwise fall back to the
    main checkout's, found as the parent of the common .git dir."""
    local = root / "graphify-out"
    if local.exists():
        return local
    try:
        common_dir = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return local
    return Path(common_dir).parent / "graphify-out"


parser = argparse.ArgumentParser(usage=__doc__)
parser.add_argument("prefix")
parser.add_argument("--grep", dest="word", default=None)
parser.add_argument("--tests", action="store_true")
opts = parser.parse_args()

prefix = opts.prefix
if Path(prefix).exists():
    rel = Path(prefix).resolve().relative_to(root).as_posix()
    prefix = rel + "/" if Path(prefix).is_dir() else rel
word = opts.word.lower() if opts.word else None

graph_path = find_graphify_out() / "graph.json"
if not graph_path.exists():
    sys.exit(
        f"{graph_path} missing: refresh it with the QML-preserving procedure in the "
        "code-graph skill (.claude/skills/code-graph/SKILL.md), not a bare full /graphify build"
    )
g = json.loads(graph_path.read_text())
nodes = {n["id"]: n for n in g["nodes"]}
edges = g.get("links") or g.get("edges") or []
MAX_SITES = 12


def src(n):
    return n.get("source_file") or ""


def is_test(path):
    return path.endswith("_test.go") or "/mocks/" in path


def git_grep(pattern, *paths):
    res = subprocess.run(
        ["git", "grep", "-InE", pattern, "--", *paths, ":!*_test.go", ":!core/ent/*", ":!core/internal/mocks/*"],
        cwd=root, capture_output=True, text=True,
    )
    return [":".join(line.split(":", 2)[:2]) for line in res.stdout.splitlines()]


_method_calls = None


def method_call_sites(name):
    """file:line of every `.name(` in core Go sources; one git grep, indexed on first use."""
    global _method_calls
    if _method_calls is None:
        _method_calls = {}
        res = subprocess.run(
            ["git", "grep", "-InoE", r"\.[A-Za-z_][A-Za-z0-9_]*\(", "--", "core",
             ":!*_test.go", ":!core/ent/*", ":!core/internal/mocks/*"],
            cwd=root, capture_output=True, text=True,
        )
        for line in res.stdout.splitlines():
            path, lineno, match = line.split(":", 2)
            sites_for = _method_calls.setdefault(match[1:-1], [])
            if not sites_for or sites_for[-1] != f"{path}:{lineno}":
                sites_for.append(f"{path}:{lineno}")
    return _method_calls.get(name, [])


def sites(hits):
    more = f" (+{len(hits) - MAX_SITES} more)" if len(hits) > MAX_SITES else ""
    return ", ".join(hits[:MAX_SITES]) + more


def handler_after(hit):
    """Name of the handle*() function called within a few lines of an IPC `case`."""
    path, line = hit.rsplit(":", 1)
    lines = (root / path).read_text().splitlines()[int(line) - 1:int(line) + 4]
    for text in lines:
        if m := re.search(r"\b(handle\w+)\(", text):
            return m.group(1)
    return None


out_calls, in_calls = {}, {}
for e in edges:
    if e.get("relation") != "calls":
        continue
    out_calls.setdefault(e["source"], []).append(e)
    in_calls.setdefault(e["target"], []).append(e)

matched = 0
for nid, n in sorted(nodes.items(), key=lambda kv: (src(kv[1]), kv[1].get("source_location") or "")):
    path, label = src(n), n["label"]
    if not path.startswith(prefix) or (is_test(path) and not opts.tests):
        continue
    if word and word not in label.lower():
        continue
    method = re.fullmatch(r"\.(\w+)\(\)", label) if path.endswith(".go") else None
    ipc = nid.startswith("ipc_method_")
    if nid not in out_calls and nid not in in_calls and not method and not ipc:
        continue
    matched += 1
    callees = [
        f"{nodes.get(e['target'], {}).get('label', e['target'])}@{e.get('source_location') or '?'}"
        for e in out_calls.get(nid, [])
    ]
    caller_nodes = [
        nodes[e["source"]] for e in in_calls.get(nid, [])
        if e["source"] in nodes and (opts.tests or not is_test(src(nodes[e["source"]])))
    ]
    print(f"## {label}  {path}:{n.get('source_location') or ''}  [{nid}]")
    if callees:
        print("   -> " + ", ".join(callees))
    if caller_nodes:
        print("   <- " + ", ".join(f"{c['label']}({Path(src(c)).name})" for c in caller_nodes))
    if method and not any(src(c) != path for c in caller_nodes):
        hits = method_call_sites(method.group(1))
        print("   ~ name matches (check receiver): " + (sites(hits) or "none"))
    if ipc:
        hits = git_grep(rf'case .*"{re.escape(label)}"', "core/internal/ipc")
        found = []
        for h in hits:
            handler = handler_after(h)
            found.append(f"{h} -> {handler + '()' if handler else '(inline in case)'}")
        print("   ~ handler: " + (", ".join(found) or "not found; check router.go prefixes"))

if not matched:
    sys.exit(f"no functions under '{prefix}'" + (f" matching '{opts.word}'" if word else "") +
             " (path is relative to the repo root; is the file ignored by .graphifyignore?)")
