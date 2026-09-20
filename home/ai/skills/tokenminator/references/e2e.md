<!--
Purpose: How to test a browser UI with a scripted local Playwright suite so a run costs a few lines of context.
Type: how-to
-->

# Scripted Browser Tests

Audience: the agent fixing a Playwright or browser MCP finding.

Driving a browser through an MCP server returns a page snapshot on every
step. A scripted test costs tokens once, when it is written.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [Choose the Cheapest Tool](#choose-the-cheapest-tool)
- [Make the Suite Deterministic](#make-the-suite-deterministic)
- [Make the Output Compact](#make-the-output-compact)
- [Judge Visuals from One Screenshot](#judge-visuals-from-one-screenshot)
- [Verify](#verify)
- [Playwright Facts](#playwright-facts)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `PW-REPORTER` | Use the `line` or `dot` reporter, plus JSON to a file. |
| `PW-RETRIES` | Set `retries: 0` and fix the flaky test. |
| `PW-SLEEP` | Replace `waitForTimeout` with a condition. |
| `PW-SERVER` | Let the config start the app with `webServer`. |
| `PW-REUSE` | Set `reuseExistingServer: false`. |
| `PW-MEDIA`, `PW-TRACE` | Record with `trace: "retain-on-failure"` and no video. |
| `MCP-BROWSER` | Move the browser MCP to a subagent, or remove it. |

## Choose the Cheapest Tool

| Need | Use |
| --- | --- |
| Prove behavior works | Run the scripted suite. |
| Behavior has no test yet | Write the test, then run it. |
| Judge how something looks | Read one named screenshot the test wrote. |
| Explore a page nobody has scripted | Browser MCP on a subagent, once. |

After exploring with an MCP, turn what you learned into a test.

## Make the Suite Deterministic

- **The config starts everything.** `webServer` launches each service and
  waits on a real health URL. Set `reuseExistingServer: false`.
- **Fresh state per run.** Create data in a temporary directory and remove
  it on exit. Use ports the developer's own stack does not use.
- **Mock the outside world by default.** Models, identity providers, and
  third-party APIs get local fakes. A real one is an explicit opt-in.
- **No retries.** A flaky test must fail loudly.
- **No fixed sleeps.** Wait with `expect`, `waitForResponse`, or a helper
  that awaits the specific request.
- **Stable locators.** Prefer `getByRole` and `getByTestId`.
- **One worker when state is shared.** Add workers only with isolated state.

## Make the Output Compact

```ts
reporter: [["line"], ["json", { outputFile: ".check/e2e.json" }]],
use: { trace: "retain-on-failure" },
```

The `line` reporter prints failures with `spec.ts:line:col`, the expected
and received values, and a code frame. That is enough to act on. Open a
trace only when it is not.

Reach the suite through the check entry point. Browser tests are slow, so
run them on request or before handoff, not on every impacted check.

## Judge Visuals from One Screenshot

Scripts cannot judge whether a layout looks right. Give the agent one image
and keep the rest out of context.

```ts
await page.screenshot({ path: testInfo.outputPath("dashboard-empty.png") });
```

1. Name the file for what it shows.
2. Run the one test that writes it.
3. Read that single image.
4. Assert facts that can be checked, such as a CSS value or a count.

## Verify

1. Run the suite twice in a row. Both runs pass with no manual setup.
2. Break one assertion. The output names the file and line, in a few lines.
3. Confirm a passing run prints a short summary and writes no video.
4. Re-run the audit and confirm the code cleared.

## Playwright Facts

| ID | Fact | Verified | Version | Source |
| --- | --- | --- | --- | --- |
| PL-01 | The `line` and `dot` reporters print each failure inline as it happens. | 2026-09-19 | docs | playwright.dev/docs/test-reporters |
| PL-02 | `["json", { outputFile }]` writes the JSON report to a file. | 2026-09-19 | docs | playwright.dev/docs/test-reporters |
| PL-03 | `--reporter=<name>` on the command line overrides the config. | 2026-09-19 | docs | playwright.dev/docs/test-reporters |
| PL-04 | The HTML reporter needs `open: "never"` to stop it opening a browser. | 2026-09-19 | docs | playwright.dev/docs/test-reporters |
| PL-05 | `webServer` accepts an array, and each entry takes `url`, `timeout`, and `reuseExistingServer`. | 2026-09-19 | docs | playwright.dev/docs/test-webserver |
| PL-06 | With no `reporter` set, Playwright uses `list` locally and `dot` on CI. | 2026-09-19 | unverified | playwright.dev/docs/test-reporters |
