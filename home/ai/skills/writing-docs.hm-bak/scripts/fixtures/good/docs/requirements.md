<!--
Purpose: The functional and non-functional requirements, grouped by domain, with status and evidence.
Type: requirements
-->

# Requirements

Audience: product owners and maintainers checking what the product must do.

## Dashboard

### Functional

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| DASH-001 | A clinician MUST be able to reopen a saved dashboard by URL without replaying chat. | Implemented | [api.ts](../src/api.ts) |

### Non-Functional

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| DASH-N01 | The system MUST persist every dashboard change atomically with a revision check. | Implemented | [api.ts](../src/api.ts) |
