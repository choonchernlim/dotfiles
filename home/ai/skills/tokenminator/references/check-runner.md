<!--
Purpose: The contract a project's single check entry point must meet, and the lessons that shaped it.
Type: how-to
-->

# Check Runner

Audience: the agent building or adapting a project's check entry point.

Validation is the most repeated work in a session. This skill ships no
runner. It states the contract, and you build it for the project's stack.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [The Contract](#the-contract)
- [Report Findings, Not Logs](#report-findings-not-logs)
- [Define Each Check Once](#define-each-check-once)
- [Traps Found in Practice](#traps-found-in-practice)
- [Verify](#verify)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `RUN-ENTRY` | Create one entry point, such as `scripts/check`. |
| `RUN-UNDOC` | Name the entry point in `AGENTS.md`. |
| `RUN-NOSUMMARY` | Write a machine-readable summary file. |
| `RUN-NOISY` | Send each tool's output to its own log file. |
| `CI-DUP` | Make CI call the entry point. |

## The Contract

Reuse an existing entry point when there is one. Wrap the tools the project
already has before adding new ones.

| Requirement | Detail |
| --- | --- |
| One command | `scripts/check`, a `make check` target, a package `check` script, or `nix flake check` when `flake.nix` declares `checks`. |
| Pinned tools | Versions come from one file, and a `doctor` mode verifies them. |
| Scopes | `--impacted` for changed paths during work, `--full` before handoff. |
| Exit codes | 0 pass, 1 findings in the code, 2 environment not ready. |
| Quiet output | One `[PASS]` or `[FAIL]` line per check, with its duration. |
| Logs | Each check writes to its own file, such as `.check/logs/<run>/<id>.log`. |
| Summary | One JSON file lists every check with status, duration, and findings. |
| Safe fixes | A `fix` mode applies formatters and safe autofixes only. |

Exit code 2 matters. It tells the agent to repair the environment, not the
code.

## Report Findings, Not Logs

The last lines of a log rarely explain a failure. Parse each tool's machine
format into findings, and print the first few under the `[FAIL]` line.

```json
{"id": "api-pytest", "status": "failed", "findingCount": 2,
 "findings": [{"file": "tests/test_a.py", "line": 42, "rule": null, "message": "assert 1 == 2"}]}
```

| Tool | Flag | What to parse |
| --- | --- | --- |
| ruff | `--output-format=concise` | `path:line:col: CODE message` |
| mypy | default | `path:line: error: message [code]` |
| pytest | `-q -rf`, with `COLUMNS=200` set | `FAILED path::test - message` |
| eslint | `--format json --output-file <file>` | the JSON report |
| vitest | `--reporter=json --outputFile.json=<file>` | the JSON report |
| terraform validate | `-json` | `diagnostics` |
| terraform test | `-json` | diagnostic and failed run events |
| tflint | `--format=compact` | `path:line:col: message` |

pytest cuts each summary line to the terminal width. Captured output has
no terminal, so the width is 80 columns and a long test name loses its
` - message`. Set `COLUMNS` for the check. Fill a missing line number or
message from the traceback's `path:line: message` line for the same file.

Report one finding per failure. Apply the `path:line: message` pattern
alone only when the tool's own format matched nothing, and the log tail
after that. Both patterns on one log count each failure twice.

Cap the list at 20 and record the total. Record each log's size in bytes,
so the saving is measured and not guessed.

## Define Each Check Once

Command lists copied between CI, a local mirror script, and the runner
always drift.

1. Define each check once, as data: id, command, folder, and when it applies.
2. Tag who runs it in CI. `template` means a shared upstream pipeline already
   runs it. `repo` means this repository must.
3. Locally, `--full` runs everything. In CI, `--ci` runs only `repo` checks,
   so nothing runs twice.
4. CI calls the entry point. Delete the hand-kept mirror script.
5. Put tool flags in configuration files, not on the command line.

## Traps Found in Practice

- **One id wrapping many tools.** A failure then yields one combined log.
  Give every tool its own check id.
- **Silent fan-out.** A path the runner does not recognize can trigger every
  check. Record which path caused it, and classify configuration paths.
- **Explicit files bypass excludes.** Linters ignore exclude lists for files
  passed by name. Set the tool's force-exclude option.
- **Autofix through symlinks.** A formatter can rewrite vendored content
  through a link. Skip agent and vendor folders in the fix mode.
- **Mutable pins.** A checksum pinned to a URL that serves changing content
  breaks without warning. Vendor the file into the repository.
- **Flags that differ from CI.** They produce "green here, red there". Keep
  them in config so both invocations are identical.
- **Exclusions only the local runner knows.** A shared CI template will not
  honor them. Record exceptions in a file both sides read, such as a baseline.

## Verify

1. Break one test on purpose and run the full check.
2. Confirm the output names that check alone and shows `file:line` inline.
3. Confirm every other check still reports separately.
4. Confirm a passing run prints one line per check and nothing else.
5. Re-run the audit and confirm the code cleared.
