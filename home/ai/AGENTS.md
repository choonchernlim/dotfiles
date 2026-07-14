# global agent instructions

## Writing style

- Never use the em dash "—"; use a plain dash "-" instead.

## Version control

- Never add your own agent name as a co-author in commit messages.
- Never manually modify CHANGELOG.md or other files marked as auto-generated.

## Engineering priorities

- When making technical decisions, do not weigh development cost heavily. Prefer quality, simplicity, robustness, scalability, and long-term maintainability.

## Bug-fixing & testing workflow

- When fixing a bug, first reproduce it end-to-end, as closely as possible to how an end user would experience it. This ensures the fix addresses the real problem.
- When end-to-end testing a product, scrutinize the UI and aim for pixel-perfection. Fix anything that looks off along the way, even if unrelated to the current task.
- Hold the same standard for engineering excellence: fix lint errors, test failures, and test flakiness you encounter, even if unrelated to what you're currently working on.
