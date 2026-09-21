#!/usr/bin/env python3
"""Path self-test for the root AGENTS.md. Copy this file to scripts/ and never edit it.

Purpose: fail when a backticked path in AGENTS.md no longer exists, so the
orientation both agents read at session start cannot drift from the tree.
Invariants: the managed rules block is cut out; a path git ignores may be absent;
a run that checked no path fails, so an empty table cannot pass.
Usage: python3 scripts/test_agents_md.py
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AGENTS = os.path.join(ROOT, "AGENTS.md")
RULES_BLOCK = re.compile(r"<!-- BEGIN:tokenminator-rules.*?<!-- END:tokenminator-rules -->", re.S)


def ignored(path: str) -> bool:
    """A runtime folder belongs in the file and is absent from a fresh clone."""
    return subprocess.run(["git", "-C", ROOT, "check-ignore", "-q", path]).returncode == 0


def main() -> int:
    with open(AGENTS, encoding="utf-8") as fh:
        text = RULES_BLOCK.sub("", fh.read())
    candidates = [c for c in re.findall(r"`([^`\s]+)`", text) if "/" in c or c.endswith(".md")]
    paths = [c for c in candidates if "<" not in c]
    missing = [p for p in paths if not ignored(p) and not os.path.exists(os.path.join(ROOT, p))]
    if not paths:
        print("AGENTS.md names no paths; the test checked nothing")
        return 1
    if missing:
        print("\n".join(f"AGENTS.md names a path that does not exist: {p}" for p in missing))
        return 1
    print(f"ok: {len(paths)} paths in AGENTS.md exist or are ignored runtime state")
    return 0


if __name__ == "__main__":
    sys.exit(main())
