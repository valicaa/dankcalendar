"""Shared graphify-out/ resolution for graph-calls.py and graph-qml.py.

graphify-out/ is excluded from git (.git/info/exclude), so it exists only in the checkout
that built it — normally the main checkout.
"""
import subprocess
from pathlib import Path


def _git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=True).stdout.strip()


def resolve(root):
    """graphify-out/ for `root`: this checkout's if it has a graph, else the main checkout's
    (checks graph.json, not just the dir — graphify's cache calls can leave a bare
    graphify-out/cache/ in a worktree with no graph.json in it)."""
    local = root / "graphify-out"
    if (local / "graph.json").exists():
        return local
    try:
        common_dir = _git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    except (subprocess.CalledProcessError, OSError):
        return local
    return Path(common_dir).parent / "graphify-out"


def main_checkout(root):
    """The checkout `root`'s git dir belongs to — itself, or the main checkout if `root` is a
    linked worktree."""
    return Path(_git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")).parent


def is_linked_worktree(root):
    """True when `root` is a linked worktree rather than the main checkout."""
    try:
        return _git(root, "rev-parse", "--path-format=absolute", "--git-dir") != \
            _git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    except (subprocess.CalledProcessError, OSError):
        return False
