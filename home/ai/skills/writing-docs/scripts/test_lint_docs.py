#!/usr/bin/env python3
"""Fixture self-test for lint_docs.py.

Purpose: prove the linter accepts the good fixture set and raises the expected
code for every bad fixture, so a rule change cannot silently disable a check.
Usage: python3 scripts/test_lint_docs.py
"""
from __future__ import annotations

import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LINT = os.path.join(HERE, "lint_docs.py")
GOOD = os.path.join(HERE, "fixtures", "good")
BAD = os.path.join(HERE, "fixtures", "bad")

EXPECTED = {
    "hdr.md": "HDR",
    "hdr-type.md": "HDR",
    "ttl.md": "TTL",
    "ttl-readme.md": "TTL",
    "hcase.md": "HCASE",
    "empty.md": "EMPTY",
    "toc-missing.md": "TOC",
    "toc-order.md": "TOC",
    "toc-adr.md": "TOC",
    "cap.md": "CAP",
    "fence.md": "FENCE",
    "run.md": "RUN",
    "sent.md": "SENT",
    "para.md": "PARA",
    "cell.md": "CELL",
    "bul.md": "BUL",
    "list.md": "LIST",
    "h2n.md": "H2N",
    "word.md": "WORD",
    "meta.md": "META",
    "link.md": "LINK",
    "mmd-direction.md": "MMD",
    "mmd-click.md": "MMD",
    "mmd-table.md": "MMD",
    "mmd-small.md": "MMD",
    "mmd-label.md": "MMD",
    "mmd-lead.md": "MMD",
    "mmd-disconnected.md": "MMD",
    "mmd-sequence.md": "MMD",
}
EXPECTED_COUNTS = {
    "link.md": ("LINK", 5),
    "word.md": ("WORD", 3),
    "mmd-label.md": ("MMD", 5),
    "mmd-sequence.md": ("MMD", 3),
}


def run(paths: list[str], root: str) -> tuple[int, str]:
    proc = subprocess.run([sys.executable, LINT, *paths, "--root", root], capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main() -> int:
    failures: list[str] = []

    good = sorted(glob.glob(os.path.join(GOOD, "**", "*.md"), recursive=True))
    code, out = run(good, GOOD)
    if code != 0:
        failures.append(f"good fixtures should pass but returned {code}:\n{out}")

    for name, expected in sorted(EXPECTED.items()):
        path = os.path.join(BAD, name)
        code, out = run([path], BAD)
        if code == 0 or f" {expected} " not in out:
            failures.append(f"{name}: expected code {expected}, got:\n{out}")
        if name in EXPECTED_COUNTS:
            want_code, want_n = EXPECTED_COUNTS[name]
            got = out.count(f" {want_code} ")
            if got != want_n:
                failures.append(f"{name}: expected {want_n} x {want_code}, got {got}:\n{out}")

    code, out = run([os.path.join(BAD, "dup-a.md"), os.path.join(BAD, "dup-b.md")], BAD)
    if " DUP " not in out:
        failures.append(f"dup-a/dup-b: expected DUP, got:\n{out}")

    code, out = run([os.path.join(BAD, "dup-c.md"), os.path.join(BAD, "dup-d.md")], BAD)
    if " DUP " not in out:
        failures.append(f"dup-c/dup-d: expected DUP for a paraphrase, got:\n{out}")

    if failures:
        print("\n\n".join(failures))
        print(f"\n{len(failures)} failure(s)")
        return 1
    print(f"ok: good set passes, {len(EXPECTED)} bad fixtures raise their codes, exact and paraphrased DUP detected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
