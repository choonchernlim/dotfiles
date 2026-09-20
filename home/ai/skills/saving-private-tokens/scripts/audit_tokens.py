#!/usr/bin/env python3
"""Deterministic audit of what makes coding agents burn tokens in a repository.

Purpose: turn token-saving review into mechanical findings, so every project is
judged the same way by Claude Code and Codex without spending model tokens.
Invariants: standard library only; runs on Python 3.9 and later; one stable code per rule;
never reads a large file in full; the only mutation is --fix-rules-block.
Exit codes: 0 clean (notes allowed), 1 findings, 2 cannot run.
Usage: audit_tokens.py [ROOT] [--format human|json] [--fix-rules-block]
       [--print-rules-block] [--list-codes] [--limit KEY=N]... [--ignore CODE]...
       [--today YYYY-MM-DD] [--facts DIR]
"""
from __future__ import annotations

import argparse
import datetime
import fnmatch
import glob
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass

try:
    import tomllib
except ImportError:  # Python 3.10
    tomllib = None  # type: ignore[assignment]

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FACTS = os.path.join(os.path.dirname(HERE), "references")
IGNORE_FILE = ".agents/saving-private-tokens.json"
HEAD_BYTES = 65536
STREAM_CAP = 1_048_576
HUMAN_CAP_PER_CODE = 5

RULES_VERSION = 1
RULES_NAME = "saving-private-tokens-rules"
RULES_BEGIN = f"<!-- BEGIN:{RULES_NAME} v{RULES_VERSION} -->"
RULES_END = f"<!-- END:{RULES_NAME} -->"
RULES_BEGIN_RE = re.compile(rf"<!-- BEGIN:{RULES_NAME} v(\d+) -->")
RULES_BODY = """## Token Discipline

- Run checks through the project's single check entry point. Read its summary first, then only the failing check's log.
- Read files in slices with offset and limit. Search first, then open the matching range.
- Never open lockfiles, generated files, or anything under Do Not Read. Ask the package manager instead (`uv tree`, `bun pm ls`, `go list -m all`).
- Prefer quiet and JSON flags over prose output. Send long output to a file and read only the part you need.
- Hand wide searches to a subagent and keep only its conclusion.
- Script anything done twice. Measure durations and log sizes before optimizing a check.
- Test browsers with the scripted Playwright suite. Open one named screenshot only for a visual judgment.
- Use a browser MCP only to explore an unscripted page once, then turn what you learned into a test.
- Managed by the saving-private-tokens skill. Do not edit by hand. Refresh with its audit script and --fix-rules-block."""

LIMITS = {
    "ins": 8000,  # bytes per instruction file
    "chain": 32768,  # bytes for a root-to-leaf AGENTS.md chain (Codex default cap)
    "fork": 15,  # non-blank CLAUDE.md lines beyond the import
    "rootskills": 8,  # skills at the repository root scope
    "rootchars": 3000,  # description characters at the root scope
    "scopechars": 6000,  # description characters at a nested scope
    "desc": 1024,  # characters in one skill description
    "large": 40000,  # bytes before a data file needs a read deny
    "small": 2000,  # lockfiles and generated files below this cost too little to flag
    "factdays": 90,  # age before a stamped tool fact is stale
}

# code: (severity, impact, playbook, what it means)
CODES = {
    "CFG-PARSE": ("high", "D", "context-diet", "agent config file is not valid JSON"),
    "AGT-MISSING": ("high", "S/M", "instruction-files", "no root AGENTS.md"),
    "CLD-IMPORT": ("high", "S/L", "instruction-files", "CLAUDE.md does not bridge to AGENTS.md"),
    "CLD-FORK": ("low", "D", "instruction-files", "CLAUDE.md carries its own instructions"),
    "RULES-MISSING": ("med", "L", "instruction-files", "working-rules block is absent"),
    "RULES-OUTDATED": ("med", "L", "instruction-files", "working-rules block is an old version"),
    "RULES-EDITED": ("med", "D", "instruction-files", "working-rules block was edited or is malformed"),
    "ORIENT-MISSING": ("med", "S/XL", "instruction-files", "no orientation section"),
    "DNR-MISSING": ("med", "R/XL", "instruction-files", "no Do Not Read section"),
    "DNR-UNLISTED": ("low", "R", "instruction-files", "costly file is not named under Do Not Read"),
    "PATH-DEAD": ("med", "D", "instruction-files", "instruction file names a path that does not exist"),
    "INS-LONG": ("med", "S", "instruction-files", "instruction file is over budget"),
    "SKILL-DUP": ("med", "S/D", "context-diet", "skill is copied into both agent trees"),
    "SKILL-LINK": ("med", "D", "context-diet", "skill trees are not one copy plus relative links"),
    "SKILL-BUDGET": ("med", "S/M", "context-diet", "too much skill listing at one scope"),
    "SKILL-DESC": ("low", "S", "context-diet", "skill description is too long"),
    "DENY-MISSING": ("high", "R/XL", "context-diet", "costly file has no Claude read deny"),
    "DENY-DEAD": ("low", "D", "context-diet", "read deny matches nothing"),
    "MCP-BROWSER": ("med", "S+L", "e2e", "browser MCP configured beside a scripted suite"),
    "RUN-ENTRY": ("high", "L/L", "check-runner", "no single check entry point"),
    "RUN-UNDOC": ("med", "L", "check-runner", "check entry point is not named in AGENTS.md"),
    "RUN-NOSUMMARY": ("med", "L", "check-runner", "check entry point has no machine-readable result"),
    "RUN-NOISY": ("med", "L", "check-runner", "check entry point does not quiet its tools"),
    "CI-DUP": ("med", "D", "check-runner", "CI repeats tool commands outside the entry point"),
    "HOOK-ONE": ("med", "D", "hooks", "hooks exist for one agent only"),
    "HOOK-DIFF": ("med", "D", "hooks", "Claude and Codex hooks differ"),
    "HOOK-HOME": ("low", "D", "hooks", "hook logic lives inside an agent folder"),
    "PW-REPORTER": ("med", "L/M", "e2e", "Playwright reporter is not compact"),
    "PW-RETRIES": ("med", "L", "e2e", "Playwright retries hide flaky tests"),
    "PW-SLEEP": ("med", "L/D", "e2e", "fixed sleep in a browser test"),
    "PW-SERVER": ("med", "L", "e2e", "Playwright config does not start the app"),
    "PW-REUSE": ("low", "D", "e2e", "Playwright reuses a running server"),
    "PW-MEDIA": ("low", "L", "e2e", "video or trace always on"),
    "PW-TRACE": ("low", "L", "e2e", "trace is not kept on failure only"),
    "TF-NOTEST": ("low", "L", "infrastructure", "Terraform has no offline tests"),
    "TF-NOLINT": ("low", "L", "infrastructure", "Terraform has no tflint"),
    "FACT-STALE": ("note", "D", "claude-code", "stamped tool facts are old"),
}
FAILING = {"high", "med", "low"}
SEVERITY_ORDER = {"high": 0, "med": 1, "low": 2, "note": 3}

PRUNE = {
    ".git", "node_modules", ".venv", "venv", "site-packages", ".terraform", "dist", "build",
    ".next", "__pycache__", "target", "vendor", ".mypy_cache", ".ruff_cache", ".pytest_cache",
}
FIXTURE_FOLDERS = {"fixtures", "__fixtures__", "testdata", "test-fixtures"}
LOCKFILES = {
    "uv.lock", "poetry.lock", "Pipfile.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "bun.lock", "bun.lockb", "go.sum", "Cargo.lock", "Gemfile.lock", "composer.lock",
    ".terraform.lock.hcl", "flake.lock",
}
GENERATED_GLOBS = [
    "*.min.js", "*.min.css", "*.map", "*.snap", "*_pb2.py", "*.pb.go", "*.generated.*",
    ".secrets.baseline",
]
DATA_EXTENSIONS = {".json", ".jsonl", ".csv", ".tsv", ".xml", ".svg", ".ipynb", ".txt"}
ORIENT_RE = re.compile(
    r"(?im)^##\s+(where things live|repo(sitory)? map|project (layout|structure|map)"
    r"|orientation|codebase map)\b"
)
DNR_RE = re.compile(r"(?im)^##\s+(do not read|don't read|never read)\b")
IMPORT_RE = re.compile(r"(?m)^@(\./)?AGENTS\.md\s*$")
BROWSER_MCP_RE = re.compile(
    r"(?i)playwright|puppeteer|chrome-devtools|browsermcp|browserbase|stagehand|selenium"
)
TOOL_LINE_RE = re.compile(
    r"\b(ruff|mypy|pytest|eslint|tsc|vitest|jest|golangci-lint|tflint|semgrep)\b"
    r"|\bgo (test|vet)\b|\bterraform (fmt|validate)\b|\b(bun|npm|pnpm|yarn) (run )?(lint|test)\b"
)
SUMMARY_RE = re.compile(
    r"summary\.json|results?\.json|report\.json|junit[\w-]*\.xml|\.sarif|--format"
)
QUIET_RE = re.compile(r"\.log\b|stdout\s*=|--quiet|--silent|\s-q\b|>\s*/dev/null")
ENTRY_NAMES = ("quality", "check", "ci", "verify", "validate")
ENTRY_TARGETS = ("check", "verify", "ci", "quality")
CI_GLOBS = [
    ".github/workflows/*.yml", ".github/workflows/*.yaml", "azure-pipelines*.yml",
    "*/azure-pipelines*.yml", "*/*/azure-pipelines*.yml", ".gitlab-ci.yml",
    ".circleci/config.yml", "bitbucket-pipelines.yml", "Jenkinsfile",
]


class CannotRun(Exception):
    """The audit cannot produce a trustworthy result."""


@dataclass
class Finding:
    code: str
    severity: str
    impact: str
    path: str
    line: int
    message: str
    playbook: str


class Repo:
    def __init__(self, root: str) -> None:
        self.root = os.path.abspath(root)
        if not os.path.isdir(self.root):
            raise CannotRun(f"not a directory: {root}")
        self.is_git = self._git(["rev-parse", "--is-inside-work-tree"]) == "true"
        self.all_files = self._list_files()
        # Structural checks skip sample repositories kept as test fixtures. Costly-file
        # checks still see them, because a large fixture is a real read hazard.
        self.files = [
            value for value in self.all_files
            if not FIXTURE_FOLDERS.intersection(value.split("/")[:-1])
        ]
        self.fileset = set(self.files)

    def _git(self, arguments: list[str]) -> str:
        try:
            done = subprocess.run(
                ["git", "-C", self.root, *arguments], capture_output=True, text=True, check=False
            )
        except OSError:
            return ""
        return done.stdout.strip() if done.returncode == 0 else ""

    def _list_files(self) -> list[str]:
        paths: list[str] = []
        if self.is_git:
            try:
                done = subprocess.run(
                    ["git", "-C", self.root, "ls-files", "-z", "--cached", "--others",
                     "--exclude-standard"],
                    capture_output=True, check=False,
                )
            except OSError:
                done = None
            if done is not None and done.returncode == 0:
                paths = [item.decode(errors="replace") for item in done.stdout.split(b"\0") if item]
        if not paths:
            for base, directories, names in os.walk(self.root):
                directories[:] = [name for name in directories if name not in PRUNE]
                for name in names + [d for d in directories if os.path.islink(os.path.join(base, d))]:
                    paths.append(os.path.relpath(os.path.join(base, name), self.root))
        kept = []
        for value in paths:
            value = value.replace(os.sep, "/")
            if PRUNE.intersection(value.split("/")):
                continue
            if os.path.lexists(os.path.join(self.root, value)):
                kept.append(value)
        return sorted(set(kept))

    def abs(self, relative: str) -> str:
        return os.path.join(self.root, relative)

    def size(self, relative: str) -> int:
        try:
            return os.stat(self.abs(relative)).st_size
        except OSError:
            return 0

    def head(self, relative: str, limit: int = HEAD_BYTES) -> str:
        try:
            with open(self.abs(relative), "rb") as source:
                return source.read(limit).decode("utf-8", errors="replace")
        except OSError:
            return ""

    def ignored(self, relative: str) -> bool:
        if not self.is_git or not relative:
            return False
        try:
            done = subprocess.run(
                ["git", "-C", self.root, "check-ignore", "-q", "--", relative],
                capture_output=True, check=False,
            )
        except OSError:
            return False
        return done.returncode == 0

    def named(self, basename: str) -> list[str]:
        return [value for value in self.files if value.rsplit("/", 1)[-1] == basename]

    def load_json(self, relative: str) -> tuple[object, bool]:
        """Return (value, parsed). A missing file is (None, True)."""
        if relative not in self.fileset and not os.path.isfile(self.abs(relative)):
            return None, True
        try:
            return json.loads(self.head(relative, STREAM_CAP)), True
        except ValueError:
            return None, False


class Audit:
    def __init__(self, repo: Repo, limits: dict[str, int], facts: str, today: datetime.date) -> None:
        self.repo = repo
        self.limits = limits
        self.facts = facts
        self.today = today
        self.findings: list[Finding] = []
        self.oldest_fact: tuple[str, datetime.date] | None = None
        self.instruction_files = [
            value for value in repo.files if value.rsplit("/", 1)[-1] == "AGENTS.md"
        ]
        self.root_agents = repo.head("AGENTS.md") if "AGENTS.md" in repo.fileset else ""
        self.candidates = self._costly_files()
        self.entry = self._find_entry()

    def add(self, code: str, path: str, message: str, line: int = 0) -> None:
        severity, impact, playbook, _ = CODES[code]
        self.findings.append(Finding(code, severity, impact, path, line, message, playbook))

    # ---------------------------------------------------------------- instruction files

    def check_instructions(self) -> None:
        repo = self.repo
        if "AGENTS.md" not in repo.fileset:
            self.add("AGT-MISSING", "AGENTS.md", "add a root AGENTS.md; it is the one file both agents can share")
            if "CLAUDE.md" in repo.fileset:
                self.add("CLD-IMPORT", "CLAUDE.md", "instructions live in a Claude-only file, so Codex reads none of them")
        for agents in self.instruction_files:
            folder = agents.rsplit("/", 1)[0] + "/" if "/" in agents else ""
            claude = folder + "CLAUDE.md"
            if claude not in repo.fileset:
                self.add("CLD-IMPORT", claude, f"missing; Claude Code does not load {agents} on its own")
                continue
            target = repo.abs(claude)
            if os.path.islink(target) and os.path.basename(os.readlink(target)) == "AGENTS.md":
                continue
            text = repo.head(claude)
            if not IMPORT_RE.search(text):
                self.add("CLD-IMPORT", claude, "has no `@AGENTS.md` import line")
                continue
            extra = [line for line in text.splitlines() if line.strip() and not IMPORT_RE.match(line)]
            if len(extra) > self.limits["fork"]:
                self.add("CLD-FORK", claude, f"{len(extra)} lines beyond the import; move shared rules into AGENTS.md")
        for value in repo.files:
            if value.rsplit("/", 1)[-1] in ("AGENTS.md", "CLAUDE.md") and not os.path.islink(repo.abs(value)):
                size = repo.size(value)
                if size > self.limits["ins"]:
                    self.add("INS-LONG", value, f"{size} bytes (~{size // 4} tokens every session); budget is {self.limits['ins']}")
        self._check_chain()
        if "AGENTS.md" in repo.fileset:
            self._check_rules_block()
            self._check_sections()
        self._check_paths()

    def _check_chain(self) -> None:
        sizes = {value: self.repo.size(value) for value in self.instruction_files}
        for leaf in self.instruction_files:
            parts = leaf.split("/")[:-1]
            chain = ["AGENTS.md"] + ["/".join(parts[: index + 1]) + "/AGENTS.md" for index in range(len(parts))]
            total = sum(sizes.get(value, 0) for value in chain)
            if total > self.limits["chain"]:
                finding_index = next(
                    (i for i, f in enumerate(self.findings) if f.code == "INS-LONG" and f.path == leaf), None
                )
                message = f"AGENTS.md chain is {total} bytes; Codex stops reading at {self.limits['chain']}"
                if finding_index is not None:
                    self.findings.pop(finding_index)
                self.add("INS-LONG", leaf, message)
                self.findings[-1].severity = "high"

    def _check_rules_block(self) -> None:
        text = self.root_agents
        begins = list(RULES_BEGIN_RE.finditer(text))
        ends = [match.start() for match in re.finditer(re.escape(RULES_END), text)]
        if not begins and not ends:
            self.add("RULES-MISSING", "AGENTS.md", "install it with --fix-rules-block")
            return
        line = text.count("\n", 0, begins[0].start()) + 1 if begins else 0
        if len(begins) != 1 or len(ends) != 1 or ends[0] < begins[0].end():
            self.add("RULES-EDITED", "AGENTS.md", "markers are unpaired or duplicated; repair them by hand, then refresh", line)
            return
        version = int(begins[0].group(1))
        if version < RULES_VERSION:
            self.add("RULES-OUTDATED", "AGENTS.md", f"block is v{version}, current is v{RULES_VERSION}; refresh with --fix-rules-block", line)
            return
        body = text[begins[0].end() : ends[0]].replace("\r\n", "\n").strip()
        if version > RULES_VERSION or body != RULES_BODY.strip():
            self.add("RULES-EDITED", "AGENTS.md", "block text differs from the managed text; refresh with --fix-rules-block", line)

    def _section(self, pattern: re.Pattern[str]) -> str:
        match = pattern.search(self.root_agents)
        if not match:
            return ""
        following = re.search(r"(?m)^##\s", self.root_agents[match.end() :])
        end = match.end() + following.start() if following else len(self.root_agents)
        return self.root_agents[match.start() : end]

    def _check_sections(self) -> None:
        if not ORIENT_RE.search(self.root_agents):
            self.add("ORIENT-MISSING", "AGENTS.md", "add a short 'Where Things Live' section so sessions stop re-exploring the layout")
        section = self._section(DNR_RE)
        if not self.candidates:
            return
        if not section:
            self.add("DNR-MISSING", "AGENTS.md", f"{len(self.candidates)} costly files exist and nothing tells Codex to skip them")
            return
        tokens = re.findall(r"`([^`\n]+)`", section)
        seen: set[str] = set()
        for path, _reason in self.candidates:
            base = path.rsplit("/", 1)[-1]
            if base in seen:
                continue
            listed = base in section or any(_glob_match(token, path) for token in tokens)
            if not listed:
                seen.add(base)
                self.add("DNR-UNLISTED", path, "name it under Do Not Read; that section is the only layer Codex honours")

    def _check_paths(self) -> None:
        repo = self.repo
        for agents in self.instruction_files:
            folder = agents.rsplit("/", 1)[0] if "/" in agents else ""
            in_fence = in_rules = False
            for number, line in enumerate(repo.head(agents).splitlines(), start=1):
                if line.lstrip().startswith("```"):
                    in_fence = not in_fence
                if RULES_BEGIN_RE.search(line):
                    in_rules = True
                if RULES_END in line:
                    in_rules = False
                if in_fence or in_rules:
                    continue
                for value in re.findall(r"`([^`\n]+)`", line):
                    if "/" not in value or re.search(r"[\s<${]|://", value) or value[0] in "-~@":
                        continue
                    if value.startswith("/"):
                        continue  # a system path, not a repository path
                    pattern = value.rstrip("/")
                    bases = [repo.root] + ([repo.abs(folder)] if folder else [])
                    if any(_exists(os.path.join(base, pattern)) for base in bases):
                        continue
                    # Only judge a path whose first segment is a real top-level entry;
                    # anything else is runtime output or relative to somewhere unknown.
                    first = pattern.split("/", 1)[0]
                    if not any(os.path.lexists(os.path.join(base, first)) for base in bases):
                        continue
                    # Guides often give paths relative to a sub-project.
                    suffix = re.compile(r"(^|/)" + _glob_regex(pattern) + r"(/|$)")
                    if any(suffix.search(tracked) for tracked in repo.all_files):
                        continue
                    static = re.split(r"[*?\[]", pattern, maxsplit=1)[0]
                    if repo.ignored(static) or (folder and repo.ignored(f"{folder}/{static}")):
                        continue
                    self.add("PATH-DEAD", agents, f"`{value}` does not exist", number)

    # ---------------------------------------------------------------- context diet

    def _costly_files(self) -> list[tuple[str, str]]:
        found = []
        for value in self.repo.all_files:
            base = value.rsplit("/", 1)[-1]
            if os.path.islink(self.repo.abs(value)):
                continue
            if base in LOCKFILES:
                if self.repo.size(value) >= self.limits["small"]:
                    found.append((value, "lockfile"))
            elif any(fnmatch.fnmatch(base, pattern) for pattern in GENERATED_GLOBS):
                if self.repo.size(value) >= self.limits["small"]:
                    found.append((value, "generated file"))
            elif os.path.splitext(base)[1].lower() in DATA_EXTENSIONS and self.repo.size(value) > self.limits["large"]:
                found.append((value, "large data file"))
        return found

    def _read_denies(self) -> list[str]:
        settings, parsed = self.repo.load_json(".claude/settings.json")
        if not parsed:
            self.add("CFG-PARSE", ".claude/settings.json", "invalid JSON, so its hooks and deny rules are not applied")
        if not isinstance(settings, dict):
            return []
        permissions = settings.get("permissions")
        deny = permissions.get("deny", []) if isinstance(permissions, dict) else []
        return [
            rule[len("Read(") : -1]
            for rule in deny
            if isinstance(rule, str) and rule.startswith("Read(") and rule.endswith(")")
        ]

    def check_context(self) -> None:
        repo = self.repo
        for config in (".codex/hooks.json", ".mcp.json"):
            _, parsed = repo.load_json(config)
            if not parsed:
                self.add("CFG-PARSE", config, "invalid JSON")
        denies = self._read_denies()
        uncovered: dict[str, list[tuple[str, str]]] = {}
        for path, reason in self.candidates:
            if not any(_deny_match(pattern, path) for pattern in denies):
                key = path if reason == "large data file" else path.rsplit("/", 1)[-1]
                uncovered.setdefault(key, []).append((path, reason))
        for key, group in uncovered.items():
            path, reason = max(group, key=lambda item: repo.size(item[0]))
            size = repo.size(path)
            rule = f"Read(/{path})" if reason == "large data file" else f"Read(**/{key})"
            count = f"{len(group)} files, largest " if len(group) > 1 else ""
            self.add("DENY-MISSING", path, f"{reason}: {count}{size // 1024} KB (~{size // 4} tokens per read); add `{rule}`")
        for pattern in denies:
            if pattern.startswith(("//", "~/")):
                continue
            if any(_deny_match(pattern, value) for value in repo.all_files):
                continue
            relative = (pattern[2:] if pattern.startswith("./") else pattern).lstrip("/")
            if _exists(os.path.join(repo.root, relative)):
                continue
            if repo.ignored(re.split(r"[*?\[]", relative, maxsplit=1)[0]):
                continue
            self.add("DENY-DEAD", ".claude/settings.json", f"`Read({pattern})` matches nothing")
        self._check_skills()

    def _skill_scopes(self) -> list[str]:
        scopes = set()
        for value in self.repo.files:
            match = re.search(r"(^|/)\.(agents|claude)/skills/", value + "/")
            if match:
                scopes.add(value[: match.start()] if match.start() else "")
        return sorted(scopes)

    def _check_skills(self) -> None:
        repo = self.repo
        for scope in self._skill_scopes():
            label = scope or "."
            shared = os.path.join(repo.root, scope, ".agents", "skills")
            linked = os.path.join(repo.root, scope, ".claude", "skills")
            if os.path.islink(linked):
                self.add("SKILL-LINK", f"{label}/.claude/skills", "link each skill, not the whole directory; only per-skill links are documented")
            shared_names = _skill_names(shared)
            linked_names = _skill_names(linked)
            for name in sorted(shared_names | linked_names):
                in_shared, in_linked = name in shared_names, name in linked_names
                entry = os.path.join(linked, name)
                if in_shared and in_linked and not os.path.islink(entry):
                    self.add("SKILL-DUP", f"{label}/.claude/skills/{name}", "second real copy; replace it with a relative link to .agents/skills")
                elif in_shared != in_linked:
                    missing = "Claude Code" if in_shared else "Codex"
                    self.add("SKILL-LINK", f"{label}/{'.agents' if in_shared else '.claude'}/skills/{name}", f"{missing} cannot see this skill")
                elif os.path.islink(entry):
                    target = os.readlink(entry)
                    if os.path.isabs(target) or not os.path.isfile(os.path.join(entry, "SKILL.md")):
                        self.add("SKILL-LINK", f"{label}/.claude/skills/{name}", "link is absolute or broken; use ../../.agents/skills/<name>")
            total = 0
            names = sorted(shared_names or linked_names)
            for name in names:
                base = shared if name in shared_names else linked
                length = len(_description(os.path.join(base, name, "SKILL.md")))
                total += length
                if length > self.limits["desc"]:
                    self.add("SKILL-DESC", f"{label}/{name}", f"description is {length} characters; keep it under {self.limits['desc']}")
            cap = self.limits["rootchars"] if not scope else self.limits["scopechars"]
            too_many = not scope and len(names) > self.limits["rootskills"]
            if total > cap or too_many:
                self.add("SKILL-BUDGET", f"{label}/.agents/skills", f"{len(names)} skills, {total} description characters (~{total // 4} tokens every session); scope them by directory or delete unused ones")

    # ---------------------------------------------------------------- check runner

    def _find_entry(self) -> tuple[str, list[str]] | None:
        """Return (file, ways an instruction file might name it)."""
        repo = self.repo
        for folder in ("scripts", "bin"):
            for name in ENTRY_NAMES:
                for suffix in ("", ".sh", ".py"):
                    path = f"{folder}/{name}{suffix}"
                    if path in repo.fileset:
                        return path, [path]
        for makefile, tool in (("Makefile", "make"), ("justfile", "just"), ("Justfile", "just")):
            if makefile in repo.fileset:
                match = re.search(rf"(?m)^({'|'.join(ENTRY_TARGETS)})\s*:", repo.head(makefile))
                if match:
                    return makefile, [f"{tool} {match.group(1)}"]
        for taskfile in ("Taskfile.yml", "Taskfile.yaml"):
            if taskfile in repo.fileset:
                match = re.search(rf"(?m)^\s{{2}}({'|'.join(ENTRY_TARGETS)})\s*:", repo.head(taskfile))
                if match:
                    return taskfile, [f"task {match.group(1)}"]
        package, _ = repo.load_json("package.json")
        if isinstance(package, dict) and isinstance(package.get("scripts"), dict):
            for target in ENTRY_TARGETS:
                if target in package["scripts"]:
                    return "package.json", [f"run {target}", f"npm {target}", f"bun {target}", f"pnpm {target}", f"yarn {target}"]
        if "mise.toml" in repo.fileset:
            match = re.search(rf"(?m)^\[tasks\.({'|'.join(ENTRY_TARGETS)})\]", repo.head("mise.toml"))
            if match:
                return "mise.toml", [f"mise run {match.group(1)}"]
        for config, tool in (("noxfile.py", "nox"), ("tox.ini", "tox")):
            if config in repo.fileset:
                return config, [tool]
        return None

    def _entry_text(self) -> str:
        assert self.entry is not None
        path = self.entry[0]
        text = self.repo.head(path)
        for token in set(re.findall(r"[\w./-]+\.(?:py|sh|js|mjs|ts)\b", text)):
            token = token.lstrip("./")
            if token in self.repo.fileset and token != path:
                text += "\n" + self.repo.head(token)
        return text

    def check_runner(self) -> None:
        repo = self.repo
        if self.entry is None:
            signals = _check_signals(repo)
            if signals:
                self.add("RUN-ENTRY", ".", f"found {', '.join(signals)} but no scripts/check, make check, or package `check` script; agents re-derive the commands every session")
                if len(signals) < 2:
                    self.findings[-1].severity = "med"
            return
        path, mentions = self.entry
        instructions = "\n".join(repo.head(value) for value in self.instruction_files)
        if not any(mention in instructions for mention in mentions):
            self.add("RUN-UNDOC", path, f"no AGENTS.md names `{mentions[0]}`, so agents will not find it")
        text = self._entry_text()
        if not SUMMARY_RE.search(text):
            self.add("RUN-NOSUMMARY", path, "writes no summary or report file and takes no --format flag")
        if not QUIET_RE.search(text):
            self.add("RUN-NOISY", path, "tool output is not sent to log files, so every run floods the context")
        ci_files = [value for pattern in CI_GLOBS for value in repo.files if fnmatch.fnmatch(value, pattern)]
        ci_files += [value for value in repo.files if re.fullmatch(r"scripts/[^/]*ci[^/]*\.sh", value)]
        for value in sorted(set(ci_files)):
            if value == path:
                continue
            body = repo.head(value)
            if any(mention in body for mention in mentions):
                continue
            lines = [n for n, line in enumerate(body.splitlines(), 1) if TOOL_LINE_RE.search(line)]
            if len(lines) >= 2:
                self.add("CI-DUP", value, f"{len(lines)} tool commands and no call to `{mentions[0]}`; CI and local checks will drift", lines[0])

    # ---------------------------------------------------------------- hooks

    def check_hooks(self) -> None:
        repo = self.repo
        settings, _ = repo.load_json(".claude/settings.json")
        claude = settings.get("hooks") if isinstance(settings, dict) else None
        codex_json, _ = repo.load_json(".codex/hooks.json")
        codex = codex_json.get("hooks") if isinstance(codex_json, dict) else None
        codex_path = ".codex/hooks.json"
        if not codex and ".codex/config.toml" in repo.fileset:
            raw = repo.head(".codex/config.toml")
            if re.search(r"(?m)^\[+hooks", raw):
                codex_path = ".codex/config.toml"
                if tomllib is None:
                    codex = {"unparsed": raw}
                else:
                    try:
                        codex = tomllib.loads(raw).get("hooks")
                    except tomllib.TOMLDecodeError:
                        codex = None
        if bool(claude) != bool(codex):
            present, absent = ("Claude Code", "Codex") if claude else ("Codex", "Claude Code")
            self.add("HOOK-ONE", ".claude/settings.json" if claude else codex_path, f"{present} has hooks and {absent} has none")
        elif claude and codex and claude != codex:
            self.add("HOOK-DIFF", codex_path, "hook blocks are not structurally equal; both agents should call one shared script")
        commands = re.findall(r'"command"\s*:\s*"((?:[^"\\]|\\.)*)"', json.dumps([claude, codex]))
        for command in commands:
            if re.search(r"\.(claude|codex)/(?!settings)", command):
                self.add("HOOK-HOME", codex_path if ".codex/" in command else ".claude/settings.json", "hook runs a script inside an agent folder; move it under scripts/")
                break
        else:
            strays = [v for v in repo.files if re.match(r"\.(claude|codex)/hooks/", v)]
            if strays:
                self.add("HOOK-HOME", strays[0], "hook logic inside an agent folder; move it under scripts/")

    # ---------------------------------------------------------------- e2e

    def check_e2e(self) -> None:
        repo = self.repo
        configs = [v for v in repo.files if re.fullmatch(r"(.*/)?playwright\.config\.[cm]?[jt]s", v)]
        for config in configs:
            self._check_playwright(config)
        if not configs:
            return
        servers: list[str] = []
        mcp, _ = repo.load_json(".mcp.json")
        if isinstance(mcp, dict) and isinstance(mcp.get("mcpServers"), dict):
            servers += [f"{name} {json.dumps(value)}" for name, value in mcp["mcpServers"].items()]
        hits = [".mcp.json"] if any(BROWSER_MCP_RE.search(value) for value in servers) else []
        if ".codex/config.toml" in repo.fileset:
            tables = re.findall(r"(?m)^\[mcp_servers\.[^\]]+\][^\[]*", repo.head(".codex/config.toml"))
            if any(BROWSER_MCP_RE.search(table) for table in tables):
                hits.append(".codex/config.toml")
        for path in hits:
            self.add("MCP-BROWSER", path, "a scripted suite exists; keep the browser MCP on an exploration subagent or remove it")

    def _check_playwright(self, config: str) -> None:
        repo = self.repo
        folder = config.rsplit("/", 1)[0] if "/" in config else ""
        text = _strip_comments(repo.head(config))
        hop = text
        for relative in re.findall(r"""from\s+['"](\.[^'"]+)['"]""", text):
            base = os.path.normpath(os.path.join(folder, relative)).replace(os.sep, "/")
            for suffix in ("", ".ts", ".js", ".mjs", ".mts", "/index.ts", "/index.js"):
                if base + suffix in repo.fileset:
                    hop += "\n" + _strip_comments(repo.head(base + suffix))
                    break
        reporter = re.search(r"\breporter\s*:", text)
        window = text[reporter.end() : reporter.end() + 300] if reporter else ""
        package = repo.head(f"{folder}/package.json" if folder else "package.json")
        compact = bool(re.search(r"""['"](line|dot)['"]""", window)) or bool(
            re.search(r"--reporter[=\s](line|dot)", package)
        )
        html_opens = "html" in window and not re.search(r"""open\s*:\s*['"]never['"]""", window)
        if not compact and (not reporter or html_opens or re.search(r"""['"]list['"]""", window)):
            self.add("PW-REPORTER", config, "set `line` or `dot` (plus JSON to a file); one line per test and an auto-opening HTML report waste context")
        retries = re.search(r"\bretries\s*:\s*([^,\n}]+)", text)
        if retries and re.search(r"[1-9]", retries.group(1)):
            self.add("PW-RETRIES", config, "retries turn a flaky test into a slow green one; fix the flake")
        if not re.search(r"\bwebServer\s*:", text):
            self.add("PW-SERVER", config, "no `webServer`; the agent must start the app by hand and guess when it is ready")
        if re.search(r"reuseExistingServer\s*:\s*(true|!)", hop):
            self.add("PW-REUSE", config, "reusing a running server makes results depend on leftover state")
        if re.search(r"""\b(video|trace)\s*:\s*['"]on['"]""", text):
            self.add("PW-MEDIA", config, "recording every run is slow and fills the artifacts folder")
        if not re.search(r"""\btrace\s*:\s*['"]retain-on-(first-)?failure['"]""", text):
            self.add("PW-TRACE", config, "use `trace: 'retain-on-failure'` so a failure has evidence and a pass costs nothing")
        test_dir = re.search(r"""\btestDir\s*:\s*['"]([^'"]+)['"]""", text)
        base = os.path.normpath(os.path.join(folder, test_dir.group(1) if test_dir else ".")).replace(os.sep, "/")
        prefix = "" if base == "." else base + "/"
        for value in repo.files:
            if value.startswith(prefix) and re.search(r"\.(spec|test)\.[cm]?[jt]sx?$", value):
                line = _first_line(repo.abs(value), "waitForTimeout(")
                if line:
                    self.add("PW-SLEEP", value, "wait on a condition (`expect`, `waitForResponse`), never a fixed time", line)

    # ---------------------------------------------------------------- infrastructure, freshness

    def check_infrastructure(self) -> None:
        repo = self.repo
        terraform = [value for value in repo.files if value.endswith(".tf")]
        if not terraform:
            return
        if not any(value.endswith(".tftest.hcl") for value in repo.files):
            self.add("TF-NOTEST", terraform[0].rsplit("/", 1)[0] if "/" in terraform[0] else ".", "no *.tftest.hcl; intent is only proven by a slow pipeline apply")
        if repo.named(".tflint.hcl"):
            return
        sources = [value for pattern in CI_GLOBS for value in repo.files if fnmatch.fnmatch(value, pattern)]
        sources += [v for v in repo.files if v.startswith("scripts/") or v in ("Makefile", "mise.toml", ".pre-commit-config.yaml")]
        if not any(repo.size(v) <= HEAD_BYTES and "tflint" in repo.head(v) for v in sources):
            self.add("TF-NOLINT", terraform[0].rsplit("/", 1)[0] if "/" in terraform[0] else ".", "no tflint; invalid provider values surface only at plan time")

    def check_facts(self) -> None:
        stamps: list[tuple[datetime.date, str]] = []
        for path in sorted(glob.glob(os.path.join(self.facts, "*.md"))):
            with open(path, encoding="utf-8", errors="replace") as source:
                for line in source:
                    if not line.startswith("|"):
                        continue
                    match = re.search(r"\|\s*(\d{4}-\d{2}-\d{2})\s*\|", line)
                    if match:
                        try:
                            stamp = datetime.date.fromisoformat(match.group(1))
                        except ValueError:
                            continue
                        stamps.append((stamp, line.split("|")[1].strip()))
        if not stamps:
            return
        stamp, fact = min(stamps)
        self.oldest_fact = (fact, stamp)
        age = (self.today - stamp).days
        if age > self.limits["factdays"]:
            self.add("FACT-STALE", "references", f"oldest fact {fact} is {age} days old; re-verify it before relying on tool-specific advice")

    def run(self) -> None:
        self.check_instructions()
        self.check_context()
        self.check_runner()
        self.check_hooks()
        self.check_e2e()
        self.check_infrastructure()
        self.check_facts()


# -------------------------------------------------------------------- helpers


def _stacks(repo: Repo) -> list[str]:
    markers = {
        "python": ("pyproject.toml", "requirements.txt", "setup.py"),
        "node": ("package.json",),
        "go": ("go.mod",),
        "rust": ("Cargo.toml",),
    }
    found = [name for name, files in markers.items() if any(repo.named(value) for value in files)]
    if not found and any(value.endswith(".py") for value in repo.files):
        found.append("python")
    if any(value.endswith(".tf") for value in repo.files):
        found.append("terraform")
    return found


def _exists(pattern: str) -> bool:
    """Glob that ignores the phantom folder old Pythons return for `missing/**`."""
    return any(os.path.lexists(match) for match in glob.glob(pattern, recursive=True))


def _check_signals(repo: Repo) -> list[str]:
    """What the repository already has that a single entry point would run."""
    found = []
    tests = re.compile(r"(^|/)(tests?|__tests__|e2e)/|(^|/)test_[^/]+\.py$|_test\.(py|go)$|\.(test|spec)\.[cm]?[jt]sx?$")
    if any(tests.search(value) for value in repo.files):
        found.append("tests")
    linters = re.compile(r"(^|/)(\.pre-commit-config\.yaml|\.?ruff\.toml|mypy\.ini|\.eslintrc[^/]*|eslint\.config\.[^/]+|\.golangci\.ya?ml|tsconfig\.json)$")
    configured = any(linters.search(value) for value in repo.files)
    if not configured:
        configured = any(
            re.search(r"(?m)^\[tool\.(ruff|mypy|pytest|black|pylint)", repo.head(value))
            for value in repo.named("pyproject.toml")
        )
    if configured:
        found.append("lint or type config")
    if any(value.endswith(".tf") for value in repo.files):
        found.append("terraform")
    return found


def _glob_regex(pattern: str) -> str:
    out = ""
    index = 0
    while index < len(pattern):
        if pattern.startswith("**/", index):
            out += "(?:.*/)?"
            index += 3
        elif pattern.startswith("**", index):
            out += ".*"
            index += 2
        elif pattern[index] == "*":
            out += "[^/]*"
            index += 1
        elif pattern[index] == "?":
            out += "[^/]"
            index += 1
        else:
            out += re.escape(pattern[index])
            index += 1
    return out


def _deny_match(pattern: str, path: str) -> bool:
    """Gitignore-style match of a Claude Read deny pattern against a repo path."""
    if pattern.startswith(("//", "~/")):
        return False
    anchored = pattern.startswith(("/", "./"))
    body = pattern[2:] if pattern.startswith("./") else pattern.lstrip("/")
    body = body.rstrip("/")
    if not anchored and "/" not in body.replace("**/", ""):
        body = "**/" + body.removeprefix("**/")
    return re.fullmatch(_glob_regex(body) + r"(?:/.*)?", path) is not None


def _glob_match(token: str, path: str) -> bool:
    if "/" not in token and "*" not in token:
        return False
    return _deny_match("/" + token.strip("/"), path)


def _skill_names(folder: str) -> set[str]:
    if not os.path.isdir(folder):
        return set()
    return {
        name for name in os.listdir(folder)
        if not name.startswith(".") and (os.path.isdir(os.path.join(folder, name)) or os.path.islink(os.path.join(folder, name)))
    }


def _description(skill_file: str) -> str:
    try:
        with open(skill_file, encoding="utf-8", errors="replace") as source:
            head = source.read(4096)
    except OSError:
        return ""
    if not head.startswith("---"):
        return ""
    collected: list[str] = []
    active = False
    for line in head.splitlines()[1:]:
        if line.strip() == "---":
            break
        if active:
            if line.startswith((" ", "\t")) or not line.strip():
                collected.append(line.strip())
                continue
            break
        match = re.match(r"description:\s*(.*)$", line)
        if match:
            active = True
            first = match.group(1).strip()
            if first not in (">", "|", ">-", "|-", ">+", "|+", ""):
                collected.append(first)
    return " ".join(part for part in collected if part).strip("\"'")


def _strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"(?m)(^|\s)//.*$", r"\1", text)


def _first_line(path: str, needle: str) -> int:
    read = 0
    try:
        with open(path, encoding="utf-8", errors="replace") as source:
            for number, line in enumerate(source, start=1):
                read += len(line)
                if needle in line and not line.lstrip().startswith("//"):
                    return number
                if read > STREAM_CAP:
                    break
    except OSError:
        return 0
    return 0


def rules_block() -> str:
    return f"{RULES_BEGIN}\n{RULES_BODY}\n{RULES_END}\n"


def fix_rules_block(root: str) -> str:
    path = os.path.join(root, "AGENTS.md")
    if not os.path.isfile(path):
        raise CannotRun("no root AGENTS.md to hold the rules block; create it first")
    with open(path, encoding="utf-8", newline="") as source:
        original = source.read()
    newline = "\r\n" if "\r\n" in original else "\n"
    text = original.replace("\r\n", "\n")
    begins = list(RULES_BEGIN_RE.finditer(text))
    ends = [match for match in re.finditer(re.escape(RULES_END) + r"\n?", text)]
    block = rules_block()
    if not begins and not ends:
        heading = ORIENT_RE.search(text)
        if heading:
            updated = text[: heading.start()] + block + "\n" + text[heading.start() :]
        else:
            updated = text.rstrip("\n") + "\n\n" + block if text.strip() else block
    elif len(begins) == 1 and len(ends) == 1 and ends[0].start() > begins[0].end():
        updated = text[: begins[0].start()] + block + text[ends[0].end() :]
    else:
        raise CannotRun("rules block markers are unpaired or duplicated; repair AGENTS.md by hand")
    updated = updated.replace("\n", newline) if newline != "\n" else updated
    if updated == original:
        return "unchanged"
    temporary = path + ".tmp-rules"
    with open(temporary, "w", encoding="utf-8", newline="") as target:
        target.write(updated)
    os.replace(temporary, path)
    return "updated"


def load_ignores(repo: Repo, cli: list[str]) -> dict[str, str]:
    ignores = {code: "ignored on the command line" for code in cli}
    path = repo.abs(IGNORE_FILE)
    if not os.path.isfile(path):
        return ignores
    try:
        with open(path, encoding="utf-8") as source:
            entries = json.load(source).get("ignore", {})
    except (OSError, ValueError, AttributeError) as error:
        raise CannotRun(f"{IGNORE_FILE} is not valid: {error}") from error
    for key, reason in entries.items():
        if not isinstance(reason, str) or not reason.strip():
            raise CannotRun(f"{IGNORE_FILE}: `{key}` needs a written reason")
        if key.split(":", 1)[0] not in CODES:
            raise CannotRun(f"{IGNORE_FILE}: `{key}` is not a known code")
        ignores[key] = reason
    return ignores


def is_ignored(finding: Finding, ignores: dict[str, str]) -> bool:
    for key in ignores:
        code, _, pattern = key.partition(":")
        if code == finding.code and (not pattern or fnmatch.fnmatch(finding.path, pattern)):
            return True
    return False


def render_human(findings: list[Finding], ignored: int, audit: Audit, stacks: list[str]) -> str:
    lines = []
    shown: dict[str, int] = {}
    for finding in findings:
        shown[finding.code] = shown.get(finding.code, 0) + 1
        if shown[finding.code] > HUMAN_CAP_PER_CODE:
            continue
        lines.append(
            f"{finding.code} {finding.severity} {finding.path}:{finding.line} "
            f"{finding.message} ({finding.impact}) -> {finding.playbook}.md"
        )
    for code, count in shown.items():
        if count > HUMAN_CAP_PER_CODE:
            lines.append(f"{code} ... +{count - HUMAN_CAP_PER_CODE} more (use --format json for all)")
    counts = {level: sum(1 for f in findings if f.severity == level) for level in SEVERITY_ORDER}
    fact = "none"
    if audit.oldest_fact:
        name, stamp = audit.oldest_fact
        fact = f"{name} {stamp.isoformat()} ({(audit.today - stamp).days}d)"
    lines.append(
        f"summary: {len(findings)} finding(s): {counts['high']} high, {counts['med']} med, "
        f"{counts['low']} low, {counts['note']} note, {ignored} ignored | "
        f"stacks: {','.join(stacks) or 'none'} | rules v{RULES_VERSION} | oldest fact: {fact}"
    )
    return "\n".join(lines)


def parse_limits(values: list[str]) -> dict[str, int]:
    limits = dict(LIMITS)
    for value in values:
        key, _, number = value.partition("=")
        if key not in limits or not number.isdigit():
            raise CannotRun(f"--limit expects KEY=N with KEY in {sorted(limits)}; got `{value}`")
        limits[key] = int(number)
    return limits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--root", dest="root_flag")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    parser.add_argument("--fix-rules-block", action="store_true")
    parser.add_argument("--print-rules-block", action="store_true")
    parser.add_argument("--list-codes", action="store_true")
    parser.add_argument("--limit", action="append", default=[])
    parser.add_argument("--ignore", action="append", default=[])
    parser.add_argument("--today")
    parser.add_argument("--facts", default=DEFAULT_FACTS)
    args = parser.parse_args(argv)

    if args.print_rules_block:
        sys.stdout.write(rules_block())
        return 0
    if args.list_codes:
        for code, (severity, impact, playbook, meaning) in CODES.items():
            print(f"{code} {severity} {impact} {playbook} {meaning}")
        return 0
    try:
        root = args.root_flag or args.root
        today = datetime.date.fromisoformat(args.today) if args.today else datetime.date.today()
        limits = parse_limits(args.limit)
        unknown = [code for code in args.ignore if code.split(":", 1)[0] not in CODES]
        if unknown:
            raise CannotRun(f"unknown code(s) for --ignore: {', '.join(unknown)}")
        if args.fix_rules_block:
            print(f"rules block v{RULES_VERSION}: {fix_rules_block(os.path.abspath(root))}")
        repo = Repo(root)
        ignores = load_ignores(repo, args.ignore)
        audit = Audit(repo, limits, args.facts, today)
        audit.run()
    except (CannotRun, ValueError) as error:
        print(f"audit_tokens: {error}", file=sys.stderr)
        return 2

    kept = [finding for finding in audit.findings if not is_ignored(finding, ignores)]
    ignored = len(audit.findings) - len(kept)
    kept.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.code, f.path, f.line))
    failing = any(finding.severity in FAILING for finding in kept)
    stacks = _stacks(repo)
    if args.format == "json":
        fact = audit.oldest_fact
        print(json.dumps({
            "schemaVersion": 1,
            "root": repo.root,
            "status": "findings" if failing else "clean",
            "rulesVersion": RULES_VERSION,
            "stacks": stacks,
            "counts": {level: sum(1 for f in kept if f.severity == level) for level in SEVERITY_ORDER},
            "ignored": ignored,
            "oldestFact": {"id": fact[0], "date": fact[1].isoformat()} if fact else None,
            "findings": [asdict(finding) for finding in kept],
        }, separators=(",", ":")))
    else:
        print(render_human(kept, ignored, audit, stacks))
    return 1 if failing else 0


if __name__ == "__main__":
    try:
        code = main()
        sys.stdout.flush()
    except BrokenPipeError:
        # The reader (for example `head`) closed the pipe; that is not a failure.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        code = 0
    sys.exit(code)
