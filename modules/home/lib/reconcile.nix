# mkReconcile: the single way this repo writes home-manager activation shell.
#
# Wraps the script in pkgs.writeShellApplication so that:
#   - shellcheck runs at BUILD time: a script calling a tool that is not on the
#     hermetic activation PATH fails `rebuild` instead of silently no-oping;
#   - strict mode (set -euo pipefail) is on; genuinely best-effort commands
#     (network calls, optional binaries) opt out per-command with `|| true`;
#   - tool deps are declared via `path` (runtimeInputs) instead of sprinkling
#     ${pkgs.foo}/bin/foo. jq is always available. Homebrew tools are not nix
#     packages, so they are still referenced by absolute /opt/homebrew paths.
#
# The activation entry calls the script through home-manager's `run` wrapper,
# so `--dry-run` activations print the command instead of mutating the system.
#
# Usage:
#   let mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
#   in home.activation.fooReconcile = mkReconcile {
#     name = "foo-reconcile";      # script name (kebab-case)
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
    # SC2015: the deliberate best-effort idiom `cmd && other || true`.
    # SC2016: false positive on jq filters, where $var must NOT be shell-expanded.
    excludeShellChecks = [
      "SC2015"
      "SC2016"
    ];
    text = ''
      # json_edit FILE JQ_ARG... - atomically rewrite FILE via jq (tmp + mv in
      # the same directory), so an interrupt mid-write never corrupts a state
      # file other tools also read. No-op if jq fails or produces empty output.
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
