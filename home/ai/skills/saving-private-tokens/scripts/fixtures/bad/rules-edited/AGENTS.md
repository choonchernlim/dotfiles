# Fixture

<!-- BEGIN:saving-private-tokens-rules v2 -->
## Token Discipline

- Run checks through the project's single check entry point. Read its summary first, then only the failing check's log.
- Read files in slices with offset and limit. Search first, then open the matching range.
- Never open lockfiles, generated files, or anything under Do Not Read. Ask the package manager instead (`uv tree`, `bun pm ls`, `go list -m all`).
- Prefer quiet and JSON flags over prose output. Send long output to a file and read only the part you need.
- Hand wide searches to a subagent and keep only its conclusion.
- Script anything done three times. Measure durations and log sizes before optimizing a check.
- Test browsers with the scripted Playwright suite. Open one named screenshot only for a visual judgment.
- Use a browser MCP only to explore an unscripted page once, then turn what you learned into a test.
- Managed by the saving-private-tokens skill. Do not edit by hand. Refresh with its audit script and --fix-rules-block.
<!-- END:saving-private-tokens-rules -->

## Where Things Live

Nothing yet.
