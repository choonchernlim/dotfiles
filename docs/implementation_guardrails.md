# Implementation Guardrails

Rules for porting Ansible roles into Nix. Follow these phases in order.

## 1. Audit (before writing any Nix)

- Read the full Ansible role: `tasks/`, `files/`, `templates/`, `defaults/main.yml`, and any `handlers/`.
- Produce an explicit inventory: every file path written, every directory created, every package installed, every symlink made, every permission set, every service registered.
- Check the coexistence rules in `CLAUDE.md` before touching any module. Know which files and packages Ansible still owns on this machine.

## 2. Implement

- The Nix solution must be functionally equivalent to the Ansible role - same files, same paths, same content, same behavior.
- Never overwrite or delete a file that Ansible currently manages. If Nix and Ansible would both own the same path, that is a conflict that must be resolved explicitly before proceeding.
- Use declarative Nix patterns instead of imperative steps. If a tool needs both installation and removal logic, express that as a unified Nix abstraction (e.g. a `home.file` entry or an activation script that handles both add and remove), not hardcoded imperative commands.
- When a Nix structural pattern differs significantly from what Ansible did (e.g. Ansible used a cron job; Nix would use a launchd service), propose the approach and get approval before implementing.
- When a `home.file` entry is removed, confirm no stale symlink remains at the target path. Do not leave behind empty directories or orphaned symlinks.

## 3. Verify

- Run `rebuild work` and confirm no new warnings appear beyond the documented `options.json` upstream warning.
- Diff every config file the role owns: capture the path and content before and after the rebuild. Any unintended change is a blocker.

## 4. Hand Off

- Comment out the ported role in `../mac-dev-bootstrap/main.yml` (do not delete the line).
