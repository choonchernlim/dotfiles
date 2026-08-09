# mkReconcile: the single way this repo writes home-manager activation shell.
#
# Wraps the script in pkgs.writeShellApplication so that:
#   - shellcheck runs at BUILD time - a broken script (e.g. calling a tool that
#     is not on the activation PATH) fails `rebuild` instead of silently no-oping
#     at runtime (this exact class of bug shipped once: colimaZscalerCert piped
#     through bare `awk`, absent from the hermetic activation PATH, and never ran);
#   - strict mode (set -euo pipefail) is on by default - a failing script fails
#     the activation loudly; genuinely best-effort commands (network calls,
#     optional binaries) must opt out per-command with `|| true`;
#   - runtime tool dependencies are declared via `path` (becomes runtimeInputs,
#     prepended to PATH) instead of sprinkling ${pkgs.foo}/bin/foo interpolations.
#     jq is always available. Homebrew-installed tools are still referenced by
#     absolute /opt/homebrew paths - they are not nix packages.
#
# The activation entry calls the script through home-manager's `run` wrapper,
# so `--dry-run` activations print the command instead of mutating the system.
#
# Usage (from a home module or a darwin home-manager.sharedModules entry):
#   let mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
#   in home.activation.fooReconcile = mkReconcile {
#     name = "foo-reconcile";      # derivation/script name (kebab-case)
#     after = [ "barSetup" ];      # extra DAG deps beyond writeBoundary
#     path = [ pkgs.gawk ];        # extra runtimeInputs beyond jq
#     text = ''...'';
#   };
{ pkgs, lib }:

{
  name,
  after ? [ ],
  path ? [ ],
  text,
}:

let
  script = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.jq ] ++ path;
    # SC2015 ("A && B || C is not if-then-else"): the deliberate best-effort
    # idiom `cmd && other || true` is used throughout these scripts.
    # SC2016 ("expressions don't expand in single quotes"): false positive on
    # jq filters, where $var is a jq variable that must NOT be shell-expanded.
    excludeShellChecks = [
      "SC2015"
      "SC2016"
    ];
    text = ''
      # json_edit FILE JQ_ARG... - atomically rewrite FILE via jq (tmp + mv in
      # the same directory), so an interrupt mid-write never corrupts a state
      # file that other tools (agents, docker) also read. No-op if jq fails or
      # produces empty output.
      json_edit() {
        _je_file="$1"
        shift
        _je_tmp=$(mktemp "$_je_file.XXXXXX") || return 0
        if jq "$@" "$_je_file" > "$_je_tmp" 2>/dev/null && [ -s "$_je_tmp" ]; then
          mv "$_je_tmp" "$_je_file"
        else
          rm -f "$_je_tmp"
        fi
      }

      ${text}
    '';
  };
in
lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ after) ''
  run ${script}/bin/${name}
''
