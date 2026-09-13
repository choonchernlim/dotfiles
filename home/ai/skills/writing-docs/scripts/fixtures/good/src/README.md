<!--
Purpose: What src/ owns, its entrypoints, and how to extend it.
Type: readme-folder
-->

# Source

Owns the server routes and the widget registry; does not own persistence.

## Entrypoints

- `api.ts`: the tile route other modules call.

## File Ownership

| File | Owns | Direct Callers |
| --- | --- | --- |
| [api.ts](api.ts) | Tile route | Browser |
| [widgets/registry.ts](widgets/registry.ts) | Widget registration | Tile route |

## How to Extend

Add one entry to the list in `widgets/registry.ts`; edit nothing else.

## Verification

```bash
bun run test
```
