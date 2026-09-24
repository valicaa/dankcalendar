"""Shared graphify-out/ resolution for graph-calls.py and graph-qml.py.

graphify-out/ is excluded from git (.git/info/exclude), so it exists only in the checkout
that built it. A linked worktree has none of its own; resolve() falls back to the main
checkout's, found as the parent of the common .git dir. is_fallback() tells a writing
subcommand it would be about to write another branch's source into the main checkout's graph.
"""
import subprocess
from pathlib import Path


def resolve(root):
    """graphify-out/ for `root`: this checkout's if it has a graph, else the main checkout's.

    Checks for graph.json specifically, not just the directory: graphify's semantic-cache
    functions anchor their own cache dir to `root` regardless of where the graph itself lives
    (they take no `cache_root` here), so a read-only `status`/`prompt` run against a fallback
    graph can leave a bare graphify-out/cache/ in a worktree with no graph.json in it. Treating
    that as "this checkout's own graph" would silently defeat the fallback on the next run."""
    local = root / "graphify-out"
    if (local / "graph.json").exists():
        return local
    try:
        common_dir = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return local
    return Path(common_dir).parent / "graphify-out"


def is_fallback(root, out):
    """True when `out` isn't this checkout's own graphify-out/ — we fell back to the main
    checkout's, so writing into it would mix this checkout's (possibly different-branch)
    source into that graph."""
    return out != root / "graphify-out"


def refuse_if_fallback(root, out):
    """Exit if `out` is a fallback: a writing subcommand must not run against it."""
    if is_fallback(root, out):
        import sys
        sys.exit(f"the graph belongs to the main checkout at {out.parent}; refresh it from "
                  "there per the code-graph skill")
