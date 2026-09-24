#!/home/nozomi/.local/share/graphify-venv/bin/python
"""Keep the QML part of the code graph current. graphify has no QML parser and its file
detection skips .qml, so neither `graphify update .` nor `/graphify --update` touches QML;
a full `/graphify` rebuild drops the QML nodes. QML is extracted by LLM subagents instead,
cached per file in graphify's semantic cache, and merged back with this tool.

  graph-qml.py status             changed/new/deleted QML vs cache and graph (no LLM, ~1s)
  graph-qml.py prompt N FILE...   print the extraction prompt for one subagent (chunk N)
  graph-qml.py merge              cache graphify-out/.qml_chunk_*.json, then merge every
                                  cached QML file into graph.json (also restores QML after
                                  a full rebuild) and prune deleted files

Flow: status -> one general-purpose subagent per ~20 changed files, each given the output of
`prompt` -> merge. Only changed files cost tokens; unchanged ones come from the cache.

status and prompt are read-only and work from a linked worktree against the main checkout's
graph. merge writes graph.json; from a worktree it refuses, since it would merge that
checkout's (possibly different-branch) QML into the main checkout's graph — run it from there.
"""
import glob
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

sys.path.insert(0, str(Path(__file__).resolve().parent))
import graphpaths  # noqa: E402

OUT = graphpaths.resolve(ROOT)
GRAPH = OUT / "graph.json"
FILE_TYPES = {"code", "document", "paper", "image", "rationale", "concept"}
os.chdir(ROOT)

from graphify.build import build_merge  # noqa: E402
from graphify.cache import check_semantic_cache, save_semantic_cache  # noqa: E402
from graphify.cluster import cluster  # noqa: E402
from graphify.export import to_json  # noqa: E402

PROMPT = """You are a graphify extraction subagent. Read every file listed and extract a knowledge graph fragment.

Files (QML chunk {n}), paths relative to {root}:
{files}

Project: Dank Calendar, Go daemon (core/) + Quickshell/QML UI (quickshell/). graphify has no QML parser, so you
are the only source of structure. Treat each QML file as code:
- One node per file for the component: id `{{parent_dir}}_{{filename_stem}}_{{component}}`, e.g.
  quickshell/Services/DankCalService.qml -> `services_dankcalservice_dankcalservice`;
  quickshell/shell.qml -> `quickshell_shell_shell`. Nodes for significant functions, signals and notable
  properties: `{{parent_dir}}_{{filename_stem}}_{{name}}`, e.g. `modals_eventdetailsmodal_save`.
  Lowercase, only [a-z0-9_], immediate parent dir only, no chunk suffixes.
- `calls` edges for function calls (source = caller). `references` edges for component usage and singleton
  usage (Theme, SettingsData, DankCalService, I18n, Log, ToastService, ...); a component in another quickshell
  file is referenced by that file's component id under the same rule.
- Daemon IPC method strings passed to sendRequest (e.g. "events.create"): `concept` node, id
  `ipc_method_<name with . and - as _>`, label = the exact string, plus a `calls` edge from the calling function.
  Subscription topics: `concept` node `ipc_topic_<name>`.
- file_type is `code` for components/functions and `concept` for IPC methods/topics.
- confidence: EXTRACTED (explicit in source, confidence_score 1.0) or INFERRED (exactly one of 0.95, 0.85, 0.75,
  0.65, 0.55) or AMBIGUOUS (0.1-0.3). At most 3 hyperedges (groups of 3+ nodes in one flow).
- Edges may point at component ids defined in other files; every other endpoint must be in your nodes array.

JSON schema:
{{"nodes":[{{"id":"...","label":"...","file_type":"code|concept","source_file":"quickshell/...","source_location":"L123 or null"}}],
 "edges":[{{"source":"id","target":"id","relation":"calls|references|shares_data_with|semantically_similar_to","confidence":"EXTRACTED|INFERRED|AMBIGUOUS","confidence_score":1.0,"source_file":"quickshell/...","source_location":"L123 or null","weight":1.0}}],
 "hyperedges":[{{"id":"snake_case","label":"...","nodes":["id1","id2","id3"],"relation":"participate_in|form","confidence":"EXTRACTED|INFERRED","confidence_score":0.85,"source_file":"quickshell/..."}}]}}

Write the JSON with the Write tool to exactly: {chunk}
Reply with just "done N nodes M edges"."""


def qml_files():
    listed = subprocess.run(["git", "ls-files", "quickshell/*.qml"], capture_output=True, text=True, check=True)
    return sorted(str(ROOT / p) for p in listed.stdout.split())


def graph_qml_sources():
    if not GRAPH.exists():
        return set()
    return {n.get("source_file") for n in json.loads(GRAPH.read_text())["nodes"] if (n.get("source_file") or "").endswith(".qml")}


def rel(paths):
    return [str(Path(p).relative_to(ROOT)) for p in paths]


def status():
    files = qml_files()
    _, _, _, uncached = check_semantic_cache(files, root=ROOT)
    in_graph = graph_qml_sources()
    on_disk = set(rel(files))
    missing = sorted(on_disk - in_graph - set(rel(uncached)))
    deleted = sorted(in_graph - on_disk)
    print(f"QML files: {len(files)}; need extraction: {len(uncached)}; cached but not in graph: {len(missing)}; deleted: {len(deleted)}")
    for label, items in (("extract", rel(uncached)), ("merge only", missing), ("prune", deleted)):
        for p in items:
            print(f"  {label}: {p}")
    if not (uncached or missing or deleted):
        print("QML graph is current.")


def prompt(n, files):
    missing = [f for f in files if not (ROOT / f).is_file()]
    if missing:
        sys.exit("not found (paths are relative to the repo root): " + ", ".join(missing))
    chunk = OUT / f".qml_chunk_{int(n):02d}.json"
    print(PROMPT.format(n=n, root=ROOT, files="\n".join(files), chunk=chunk))


def merge():
    graphpaths.refuse_if_fallback(ROOT, OUT)
    for c in sorted(glob.glob(str(OUT / ".qml_chunk_*.json"))):
        d = json.loads(Path(c).read_text())
        bad = [x["id"] for x in d.get("nodes", []) if x.get("file_type") not in FILE_TYPES]
        if bad or not d.get("nodes"):
            sys.exit(f"{c}: {'invalid file_type on ' + ', '.join(bad[:5]) if bad else 'no nodes'}; fix or re-run that chunk")
        saved = save_semantic_cache(d["nodes"], d.get("edges", []), d.get("hyperedges", []), root=ROOT)
        print(f"cached {saved} file(s) from {Path(c).name}")
    files = qml_files()
    nodes, edges, hyperedges, uncached = check_semantic_cache(files, root=ROOT)
    if uncached:
        print(f"warning: {len(uncached)} QML file(s) still unextracted (run status)")
    deleted = sorted(graph_qml_sources() - set(rel(files)))
    G = build_merge(
        [{"nodes": nodes, "edges": edges, "hyperedges": hyperedges}],
        graph_path=GRAPH,
        prune_sources=deleted or None,
        root=ROOT,
        dedup=False,  # fuzzy dedup merges look-alike ids, e.g. system.autostart.get into .set
    )
    to_json(G, cluster(G), str(GRAPH), force=True)
    for c in glob.glob(str(OUT / ".qml_chunk_*.json")):
        os.remove(c)
    qml_nodes = sum(1 for _, a in G.nodes(data=True) if (a.get("source_file") or "").endswith(".qml"))
    print(f"graph: {G.number_of_nodes()} nodes ({qml_nodes} QML), {G.number_of_edges()} edges; pruned {len(deleted)} deleted file(s)")


match sys.argv[1:]:
    case ["status"]:
        status()
    case ["prompt", n, *files] if files:
        prompt(n, files)
    case ["merge"]:
        merge()
    case _:
        sys.exit(__doc__)
