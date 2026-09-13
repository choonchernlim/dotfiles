<!--
Purpose: The deployments, who owns each, and the one allowed dependency direction.
Type: explanation
-->

# Architecture

Audience: all teams, to answer what exists and who owns it.

## Deployments

Two teams ship independently, and only a versioned contract crosses the line
between them.

```mermaid
sequenceDiagram
  actor Clinician as Clinician<br/>[PERSON]
  participant Browser as Dashboard UI<br/>[UI]
  participant Route as Tile Route<br/>[API]
  participant Registry as Card Registry<br/>[SERVICE]

  Clinician->>Browser: 1. Select a patient
  Browser->>Route: 2. Request one tile model
  Route->>Registry: 3. Resolve the saved capability
  Registry-->>Route: 4. Return origin and card
```

1. The clinician selects a patient, which unlocks every tile.
2. Each tile asks the server for its own model.
3. The server resolves the origin from the registry.
4. The registry answers from its cache.

| Node | Source |
| --- | --- |
| Clinician | - |
| Dashboard UI | [../src/](../src/) |
| Tile Route | [../src/api.ts](../src/api.ts) |
| Card Registry | [../src/widgets/registry.ts](../src/widgets/registry.ts) |

The UI never stores a service URL. It resolves the origin on every request,
so removing a service from the registry takes effect within one refresh.
