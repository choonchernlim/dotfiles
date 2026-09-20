# Fixture

<!-- BEGIN:saving-private-tokens-rules v2 -->
## Token Discipline

- Run checks through the project's single check entry point. Read its summary first, then only the failing check's log.
- Read files in slices with offset and limit. Search first, then open the matching range.
- Never open lockfiles, generated files, or anything under Do Not Read.
- Prefer quiet and JSON flags over prose output. Send long output to a file and read only the part you need.
- Hand wide searches to a subagent and keep only its conclusion.
- Script anything done twice. Measure durations and log sizes before optimizing a check.
- Managed by the saving-private-tokens skill. Do not edit by hand. Refresh with its audit script and --fix-rules-block.
<!-- END:saving-private-tokens-rules -->

## Where Things Live

Nothing yet.
