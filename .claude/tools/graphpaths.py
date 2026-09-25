"""Shared graphify-out/ resolution for graph-calls.py and graph-qml.py.

graphify-out/ is excluded from git (.git/info/exclude), so it exists only in the checkout
that built it — normally the main checkout.
"""
import subprocess
from pathlib import Path


def _git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, check=True).stdout.strip()


def main_checkout(root):
    """The checkout `root`'s git dir belongs to — itself, or the main checkout if `root` is a
    linked worktree."""
    return Path(_git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")).parent


def resolve(root):
    """graphify-out/ for `root`: always the main checkout's."""
    try:
        return main_checkout(root) / "graphify-out"
    except (subprocess.CalledProcessError, OSError):
        return root / "graphify-out"


def is_linked_worktree(root):
    """True when `root` is a linked worktree rather than the main checkout."""
    try:
        return _git(root, "rev-parse", "--path-format=absolute", "--git-dir") != \
            _git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    except (subprocess.CalledProcessError, OSError):
        return False
