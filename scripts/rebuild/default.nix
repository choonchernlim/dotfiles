# The `rebuild` command and its output formatter, built with writeShellApplication so
# the shipped interpreter is the tested one: pinned bash 5, strict mode, and
# shellcheck at build time (same pattern as modules/home/lib/reconcile.nix).
# The root ./rebuild.sh is a shim that `nix run`s this; the logic is ./rebuild.sh
# and ./format.sh here (shebang-less fragments, so pre-commit shellcheck skips them).
{ pkgs }:

let
  rebuild-format = pkgs.writeShellApplication {
    name = "rebuild-format";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./format.sh;
  };
in
{
  inherit rebuild-format;

  rebuild = pkgs.writeShellApplication {
    name = "rebuild";
    # sudo and darwin-rebuild come from the system PATH (runtimeInputs only prepends).
    runtimeInputs = [
      rebuild-format
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnused
    ];
    text = builtins.readFile ./rebuild.sh;
  };
}
