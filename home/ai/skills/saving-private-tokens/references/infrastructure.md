<!--
Purpose: How to check infrastructure code offline so a slow pipeline is not the only feedback loop.
Type: how-to
-->

# Infrastructure Checks

Audience: the agent fixing a Terraform finding.

When a deploy pipeline is the only test, every mistake costs a full round
trip. Most mistakes can be caught offline, in seconds, with no credentials.

## Table of Contents

- [Codes This Fixes](#codes-this-fixes)
- [What Can Be Caught Offline](#what-can-be-caught-offline)
- [Add Offline Intent Tests](#add-offline-intent-tests)
- [Add Static Checks](#add-static-checks)
- [Pay for a Failure Once](#pay-for-a-failure-once)
- [Verify](#verify)

## Codes This Fixes

| Code | Fix |
| --- | --- |
| `TF-NOTEST` | Add `*.tftest.hcl` files that run `terraform test` with mock providers. |
| `TF-NOLINT` | Add `.tflint.hcl` with the provider ruleset. |

## What Can Be Caught Offline

| Failure | Offline? | How |
| --- | --- | --- |
| Wrong reference, type, or missing key | yes | `terraform validate`, `terraform test` |
| Formatting | yes | `terraform fmt -check -recursive` |
| Logic: counts, `for_each`, preconditions | yes | `terraform test` with mock providers |
| Invalid provider value | mostly | tflint provider ruleset |
| What will change against real state | no | needs a credentialed plan |
| API rules, quota, policy, network | no | only the pipeline shows these |

## Add Offline Intent Tests

`terraform test` with `mock_provider` plans against a fake provider. It
needs `terraform init -backend=false` and no credentials.

```hcl
mock_provider "google" {}

run "mocks_stay_out_of_production" {
  command = plan
  variables { env = "p", enable_mocks = true }
  expect_failures = [google_cloud_run_v2_service.default]
}
```

- Use `command = plan` only. An apply then a destroy fails on protected
  resources.
- Assert intent: which resources exist per environment, which inputs are
  rejected, which security settings every service carries.
- Run once per real variable file, so each environment is exercised.
- Override a data source only when a test asserts its value.
- A resource with an `import` block needs `override_resource` under mocks.
- Replace text-matching tests of `.tf` files with these assertions.

Keep tests in a folder the deploy pipeline does not load, such as
`quality-tests/`, and pass `-test-directory`. An older Terraform on the
deploy side then never parses newer test syntax.

## Add Static Checks

1. Pin tflint with the project's other tools.
2. Declare the provider ruleset and its version in `.tflint.hcl`.
3. Fetch the plugin in the bootstrap step, since it needs the network.
4. Run tflint once per variable file through the check entry point.

## Pay for a Failure Once

Some failures only appear in the pipeline. Encode each one in the same
change that fixes it, so it cannot cost another round trip.

- A single-variable rule becomes a `validation` block.
- A rule across variables becomes a resource `precondition`. Cross-variable
  validation needs Terraform 1.9 or later.
- Anything else becomes a test assertion.

Record this rule in `AGENTS.md` so both agents follow it.

## Verify

1. Touch a `.tf` file and run the impacted check. It runs fmt, validate,
   tflint, and the tests in seconds with no credentials.
2. Flip a protected setting and confirm a test fails with a `file:line`.
3. Re-run the audit and confirm the code cleared.
