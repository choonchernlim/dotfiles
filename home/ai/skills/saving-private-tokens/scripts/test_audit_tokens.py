#!/usr/bin/env python3
"""Fixture self-test for audit_tokens.py.

Purpose: prove the audit accepts the good fixture and raises the expected codes
for every bad case, so a rule change cannot silently disable a check, and prove
the one mutation (--fix-rules-block) is safe to run repeatedly.
Usage: python3 scripts/test_audit_tokens.py
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "audit_tokens.py")
GOOD = os.path.join(HERE, "fixtures", "good")
BAD = os.path.join(HERE, "fixtures", "bad")
REFERENCES = os.path.join(os.path.dirname(HERE), "references")
TODAY = "2026-09-19"

# Fixture lockfiles are tiny stubs, so these cases drop the size floor.
SMALL = ["--limit", "small=0"]

# case: (extra arguments, codes the case must raise)
EXPECTED: dict[str, tuple[list[str], set[str]]] = {
    "bare": (SMALL, {"AGT-MISSING", "CLD-IMPORT", "RUN-ENTRY", "DENY-MISSING"}),
    "instructions": (
        ["--limit", "ins=300", *SMALL],
        {"RULES-MISSING", "ORIENT-MISSING", "DNR-MISSING", "PATH-DEAD", "CLD-FORK", "INS-LONG"},
    ),
    "rules-outdated": ([], {"RULES-OUTDATED"}),
    "rules-edited": ([], {"RULES-EDITED"}),
    "rules-malformed": ([], {"RULES-EDITED"}),
    "skills": (
        ["--limit", "rootchars=50", "--limit", "desc=40"],
        {"SKILL-DUP", "SKILL-LINK", "SKILL-BUDGET", "SKILL-DESC"},
    ),
    "deny": (SMALL, {"DENY-DEAD", "DNR-UNLISTED", "CFG-PARSE"}),
    "runner": ([], {"RUN-UNDOC", "RUN-NOSUMMARY", "RUN-NOISY", "CI-DUP"}),
    "hooks-one": ([], {"HOOK-ONE", "HOOK-HOME"}),
    "hooks-diff": ([], {"HOOK-DIFF"}),
    "e2e": (
        [],
        {"MCP-BROWSER", "PW-REPORTER", "PW-RETRIES", "PW-SLEEP", "PW-SERVER", "PW-REUSE",
         "PW-MEDIA", "PW-TRACE"},
    ),
    "terraform": ([], {"TF-NOTEST", "TF-NOLINT"}),
}
FIXABLE = ("instructions", "rules-outdated", "rules-edited")
STALE_CODE = "FACT-STALE"
HOME = [""]  # the home folder `run` hands to the audit; set in main
EM_DASH = chr(0x2014)  # built from its code point so this file stays free of it


def run(*arguments: str) -> tuple[int, str, str]:
    # Every run gets an empty home folder unless a case supplies one, so the
    # result never depends on the machine's real user-level config.
    done = subprocess.run(
        [sys.executable, AUDIT, *arguments], capture_output=True, text=True,
        env={**os.environ, "HOME": HOME[0]},
    )
    return done.returncode, done.stdout, done.stderr


def snapshot(root: str) -> dict[str, tuple]:
    """Path -> (link target or content hash) for everything under a folder."""
    state = {}
    for base, directories, names in os.walk(root):
        for name in directories + names:
            path = os.path.join(base, name)
            if os.path.islink(path):
                state[path] = ("link", os.readlink(path))
            elif os.path.isfile(path):
                with open(path, "rb") as source:
                    state[path] = ("file", hashlib.sha256(source.read()).hexdigest())
    return state


def codes(root: str, *extra: str) -> tuple[int, set[str]]:
    status, out, err = run(root, "--format", "json", "--today", TODAY, *extra)
    if status == 2:
        raise AssertionError(f"audit could not run on {root}: {err}")
    return status, {finding["code"] for finding in json.loads(out)["findings"]}


def outside_block(text: str) -> str:
    return re.sub(r"<!-- BEGIN:saving-private-tokens-rules v\d+ -->.*?<!-- END:saving-private-tokens-rules -->\n?", "", text, flags=re.S)


def write(root: str, relative: str, text: str) -> None:
    path = os.path.join(root, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as target:
        target.write(text)


def findings(root: str, *extra: str) -> dict[str, dict]:
    _, out, _ = run(root, "--format", "json", "--today", TODAY, *extra)
    return {finding["code"]: finding for finding in json.loads(out)["findings"]}


def user_cases() -> tuple[list[str], set[str]]:
    """The user scope reads a home folder, names the real owner, and never writes."""
    failures: list[str] = []
    raised: set[str] = set()
    empty = HOME[0]
    with tempfile.TemporaryDirectory() as scratch:
        home, owner, other = (os.path.join(scratch, name) for name in ("home", "owner", "other"))
        # `owner` is a dotfiles-style repository: the home folder links into it.
        write(owner, ".git/HEAD", "ref: refs/heads/main\n")
        write(owner, "AGENTS.md", "# Owner\n\n## Where Things Live\n\n`policy.md`\n")
        write(owner, "CLAUDE.md", "@AGENTS.md\n")
        write(owner, "policy.md", "rule\n" * 40)
        write(owner, "skills/long/SKILL.md", "---\nname: long\ndescription: " + "word " * 30 + "\n---\n")
        write(other, "AGENTS.md", "# Other\n\n## Where Things Live\n\n`AGENTS.md`\n")
        write(other, "CLAUDE.md", "@AGENTS.md\n")
        os.makedirs(os.path.join(home, ".claude"))
        os.makedirs(os.path.join(home, ".codex"))
        os.symlink(os.path.join(owner, "policy.md"), os.path.join(home, ".claude", "CLAUDE.md"))
        os.symlink(os.path.join(owner, "policy.md"), os.path.join(home, ".codex", "AGENTS.md"))
        os.symlink(os.path.join(owner, "skills"), os.path.join(home, ".claude", "skills"))
        write(home, ".claude.json", '{"mcpServers": {"demo": {"env": {"TOKEN": "secret"}}}}')
        for root in (owner, other):
            run(root, "--fix-rules-block")
        limits = ["--limit", "ins=100", "--limit", "userchars=50", "--limit", "desc=40"]
        HOME[0] = home
        try:
            before = snapshot(scratch)
            inside = findings(owner, *limits)
            status_inside, out, _ = run(owner, "--format", "json", *limits)
            outside = findings(other, *limits)
            status_outside, _, _ = run(other, *limits)
            _, human, _ = run(other, "--user", *limits)
            status_mixed, _, _ = run(other, "--user", "--fix-rules-block")
            after = snapshot(scratch)
        finally:
            HOME[0] = empty
        expected = {"USR-INS", "USR-SKILL-BUDGET", "USR-SKILL-DESC"}
        raised = set(inside) & expected
        if raised != expected:
            failures.append(f"user scope: expected {sorted(expected)}, got {sorted(inside)}")
        elif not all(inside[code]["fixable"] and inside[code]["owner"] == "this repository" for code in expected):
            failures.append("user scope: findings that resolve into the audited repository should be fixable there")
        if status_inside != 1:
            failures.append(f"user scope: a fixable user finding should fail the audit, got exit {status_inside}")
        if any(outside[code]["fixable"] or not outside[code]["owner"].endswith("owner") for code in expected & set(outside)):
            failures.append("user scope: from another repository the findings should be proposals that name the owner")
        if status_outside != 0:
            failures.append(f"user scope: proposals must not fail another repository's audit, got exit {status_outside}")
        if json.loads(out)["userScope"]["baseline"][0]["what"].count("~/") != 2:
            failures.append("user scope: one shared instruction file should be priced once for both agents")
        if "secret" in human or "demo" not in human:
            failures.append("user scope: MCP servers should be listed by name only")
        if status_mixed != 2:
            failures.append("user scope: --user with --fix-rules-block should exit 2")
        if before != after:
            failures.append("user scope: the audit changed files; it must only read")
    return failures, raised


def composed_cases() -> list[str]:
    """Behaviour that depends on what a repository contains, built in scratch folders."""
    failures: list[str] = []

    # The one write follows a link inside the repository and refuses one that leaves it.
    with tempfile.TemporaryDirectory() as scratch:
        work, elsewhere = os.path.join(scratch, "work"), os.path.join(scratch, "elsewhere.md")
        write(work, "docs/agents.md", "# Project\n")
        write(scratch, "elsewhere.md", "# Someone else's file\n")
        os.symlink("docs/agents.md", os.path.join(work, "AGENTS.md"))
        status, _, _ = run(work, "--fix-rules-block", "--no-user")
        with open(os.path.join(work, "docs", "agents.md"), encoding="utf-8") as source:
            if status == 2 or not os.path.islink(os.path.join(work, "AGENTS.md")) or "Token Discipline" not in source.read():
                failures.append("guarded write: a link inside the repository should survive and its target be updated")
        os.remove(os.path.join(work, "AGENTS.md"))
        os.symlink(elsewhere, os.path.join(work, "AGENTS.md"))
        status, _, _ = run(work, "--fix-rules-block", "--no-user")
        with open(elsewhere, encoding="utf-8") as source:
            if status != 2 or "Token Discipline" in source.read():
                failures.append("guarded write: a target outside the repository must be refused and left untouched")

    # A nix repository that ships a skill: the skill's tests are not the project's
    # tests, `nix flake check` is the entry point, and the block carries no browser rules.
    with tempfile.TemporaryDirectory() as scratch:
        write(scratch, "flake.nix", "{ outputs = _: { checks = { }; }; }\n")
        write(scratch, "AGENTS.md", "# Project\n\nRun `nix flake check`.\n\n## Where Things Live\n\n`flake.nix`\n")
        write(scratch, "CLAUDE.md", "@AGENTS.md\n")
        write(scratch, "home/skills/demo/SKILL.md", "---\nname: demo\ndescription: demo\n---\n")
        write(scratch, "home/skills/demo/scripts/test_demo.py", "def test(): pass\n")
        run(scratch, "--fix-rules-block")
        found = findings(scratch)
        if found:
            failures.append(f"nix repo: expected no findings, got {sorted(found)}")
        _, block, _ = run(scratch, "--print-rules-block")
        if "Playwright" in block or "browser MCP" in block or "uv tree" in block:
            failures.append("nix repo: the rules block carries rules for stacks the repository lacks")
        if "`nix flake metadata`" not in block:
            failures.append("nix repo: the rules block lacks the nix package-manager hint")

    # The managed block does not count against the budget, and --sections shows why.
    with tempfile.TemporaryDirectory() as scratch:
        write(scratch, "AGENTS.md", "# Project\n\n## Where Things Live\n\n" + "word " * 40 + "\n")
        write(scratch, "CLAUDE.md", "@AGENTS.md\n")
        size = os.path.getsize(os.path.join(scratch, "AGENTS.md"))
        limit = ["--limit", f"ins={size + 10}"]
        run(scratch, "--fix-rules-block")
        if "INS-LONG" in findings(scratch, *limit):
            failures.append("budget: installing the managed block pushed the file over budget")
        _, sections, _ = run(scratch, "--sections", *limit)
        if "managed rules block, not counted" not in sections or "## Where Things Live" not in sections:
            failures.append("sections: expected a row per heading and one for the managed block")

    # One costly file, both guard layers missing: the two findings sum to its cost, not double.
    with tempfile.TemporaryDirectory() as scratch:
        write(scratch, "AGENTS.md", "# Project\n\n## Where Things Live\n\n`uv.lock`\n")
        write(scratch, "CLAUDE.md", "@AGENTS.md\n")
        write(scratch, "uv.lock", "x" * 40000)
        found = findings(scratch)
        layers = [found.get("DENY-MISSING"), found.get("DNR-MISSING")]
        if not all(layers):
            failures.append(f"estimates: expected both guard findings, got {sorted(found)}")
        elif sum(layer["before"] for layer in layers) != 40000 // 4 * 3 or not all(layer["measured"] for layer in layers):
            failures.append(f"estimates: guard layers should be measured and sum to one file's cost, got {layers}")

    return failures


def main() -> int:
    with tempfile.TemporaryDirectory() as empty_home:
        HOME[0] = empty_home
        return check()


def check() -> int:
    failures: list[str] = []

    status, found = codes(GOOD)
    if status != 0 or found:
        failures.append(f"good: expected exit 0 and no findings, got exit {status} {sorted(found)}")

    covered: set[str] = set()
    for case, (extra, expected) in EXPECTED.items():
        status, found = codes(os.path.join(BAD, case), *extra)
        covered |= expected
        if status != 1:
            failures.append(f"{case}: expected exit 1, got {status}")
        missing = expected - found
        if missing:
            failures.append(f"{case}: did not raise {sorted(missing)}; raised {sorted(found)}")
    on_disk = {name for name in os.listdir(BAD) if os.path.isdir(os.path.join(BAD, name))}
    if on_disk != set(EXPECTED):
        failures.append(f"bad cases on disk and in EXPECTED differ: {sorted(on_disk ^ set(EXPECTED))}")

    status, out, _ = run(GOOD, "--format", "json", "--today", "2099-01-01")
    stale = {finding["code"] for finding in json.loads(out)["findings"]}
    if stale != {STALE_CODE} or status != 0:
        failures.append(f"stale facts: expected only {STALE_CODE} as a note with exit 0, got exit {status} {sorted(stale)}")
    covered.add(STALE_CODE)

    user_failures, user_codes = user_cases()
    failures += user_failures
    covered |= user_codes

    _, listing, _ = run("--list-codes")
    declared = {line.split()[0] for line in listing.splitlines() if line.strip()}
    if declared != covered:
        failures.append(f"codes without a fixture, or fixtures for unknown codes: {sorted(declared ^ covered)}")

    for case in FIXABLE:
        with tempfile.TemporaryDirectory() as scratch:
            work = os.path.join(scratch, case)
            shutil.copytree(os.path.join(BAD, case), work, symlinks=True)
            _, block, _ = run(work, "--print-rules-block")
            agents = os.path.join(work, "AGENTS.md")
            with open(agents, encoding="utf-8") as source:
                before = source.read()
            first, _, err = run(work, "--fix-rules-block", "--format", "json", "--today", TODAY, *EXPECTED[case][0])
            if first == 2:
                failures.append(f"{case}: --fix-rules-block could not run: {err}")
                continue
            with open(agents, encoding="utf-8") as source:
                after = source.read()
            run(work, "--fix-rules-block", "--format", "json", "--today", TODAY)
            with open(agents, encoding="utf-8") as source:
                again = source.read()
            _, remaining = codes(work, *EXPECTED[case][0])
            if remaining & {"RULES-MISSING", "RULES-OUTDATED", "RULES-EDITED"}:
                failures.append(f"{case}: a RULES code survived the fix: {sorted(remaining)}")
            if block not in after:
                failures.append(f"{case}: the fixed file does not contain the managed block verbatim")
            if after != again:
                failures.append(f"{case}: a second fix changed the file; the fix is not idempotent")
            if outside_block(before).split() != outside_block(after).split():
                failures.append(f"{case}: text outside the markers changed")

    with tempfile.TemporaryDirectory() as scratch:
        work = os.path.join(scratch, "rules-malformed")
        shutil.copytree(os.path.join(BAD, "rules-malformed"), work)
        with open(os.path.join(work, "AGENTS.md"), encoding="utf-8") as source:
            before = source.read()
        status, _, _ = run(work, "--fix-rules-block")
        with open(os.path.join(work, "AGENTS.md"), encoding="utf-8") as source:
            after = source.read()
        if status != 2 or before != after:
            failures.append("rules-malformed: expected exit 2 and an untouched file")

    with tempfile.TemporaryDirectory() as scratch:
        status, _, _ = run(scratch, "--fix-rules-block")
        if status != 2:
            failures.append("fix without AGENTS.md: expected exit 2")
        status, _, _ = run(os.path.join(scratch, "missing"))
        if status != 2:
            failures.append("missing root: expected exit 2")

    _, full, _ = run("--print-rules-block", "full")
    reference = os.path.join(REFERENCES, "instruction-files.md")
    with open(reference, encoding="utf-8") as source:
        if full not in source.read():
            failures.append("references/instruction-files.md does not show the full managed block verbatim")

    failures += composed_cases()

    stamped = 0
    for name in sorted(os.listdir(REFERENCES)):
        with open(os.path.join(REFERENCES, name), encoding="utf-8") as source:
            for number, line in enumerate(source, start=1):
                if re.match(r"\|\s*[A-Z]{2}-\d{2}\s*\|", line):
                    stamped += 1
                    if not re.search(r"\|\s*\d{4}-\d{2}-\d{2}\s*\|", line):
                        failures.append(f"{name}:{number}: fact row has no YYYY-MM-DD stamp")
    if not stamped:
        failures.append("no stamped fact rows found under references/")

    skill_root = os.path.dirname(HERE)
    for folder, _, names in os.walk(skill_root):
        if os.sep + "fixtures" in folder:
            continue
        for name in names:
            if name.endswith((".md", ".py")):
                with open(os.path.join(folder, name), encoding="utf-8") as source:
                    if EM_DASH in source.read():
                        failures.append(f"{os.path.relpath(os.path.join(folder, name), skill_root)}: contains an em dash")

    if failures:
        print("\n".join(failures))
        print(f"FAILED: {len(failures)} problem(s)")
        return 1
    print(
        f"ok: good fixture is clean, {len(EXPECTED)} bad cases raise {len(covered)} codes, "
        f"the rules-block fix is idempotent, composed and user-scope cases hold, {stamped} facts are stamped"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
