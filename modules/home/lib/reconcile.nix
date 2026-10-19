# mkReconcile: the single way this repo writes home-manager activation shell.
#
# Wraps the script in pkgs.writeShellApplication so that:
#   - shellcheck runs at BUILD time (quoting, syntax, unset variables); the
#     `activation` flake check builds every script, so this gates checks too.
#     It does not check that commands exist: a tool missing from PATH fails at
#     activation, loudly, through strict mode;
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
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils # _apply's chmod --reference is GNU-only
      pkgs.diffutils # _apply's cmp
    ]
    ++ path;
    # SC2015: the deliberate best-effort idiom `cmd && other || true`.
    # SC2016: false positive on jq filters, where $var must NOT be shell-expanded.
    excludeShellChecks = [
      "SC2015"
      "SC2016"
    ];
    text = ''
      # _apply FILE CMD... - run CMD with FILE as its last argument and replace
      # FILE with the output atomically (tmp + mv in the same directory), so an
      # interrupt mid-write never corrupts a state file other tools also read.
      # FILE keeps its mode (mktemp creates 0600). Returns 0 when FILE changed,
      # 1 when it was already up to date, and 2 when CMD failed or printed
      # nothing: FILE is then left as is and a warning names it, so a config the
      # owning app broke shows in the rebuild output.
      _apply() {
        _ap_file="$1"
        shift
        _ap_tmp=$(mktemp "$_ap_file.XXXXXX") || {
          echo "${name}: cannot write next to $_ap_file" >&2
          return 2
        }
        if ! "$@" "$_ap_file" > "$_ap_tmp" || [ ! -s "$_ap_tmp" ]; then
          rm -f "$_ap_tmp"
          echo "${name}: could not rewrite $_ap_file, left unchanged" >&2
          return 2
        fi
        if cmp -s "$_ap_file" "$_ap_tmp"; then
          rm -f "$_ap_tmp"
          return 1
        fi
        chmod --reference="$_ap_file" "$_ap_tmp"
        mv "$_ap_tmp" "$_ap_file"
      }

      # json_edit FILE JQ_ARG... - _apply through jq, best-effort.
      json_edit() {
        _je_file="$1"
        shift
        _apply "$_je_file" jq "$@" || true
      }

      ${text}
    '';
  };
in
# flake.nix (reconcileScripts) recognises a reconcile by exactly this line.
lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ after) ''
  run ${script}/bin/${name}
''
