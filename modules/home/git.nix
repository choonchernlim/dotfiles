# Feature (all 3 hosts): global git settings every machine relies on.
#
# Like zscalerGitCert in zscaler.nix, which also writes ~/.gitconfig: one key
# at a time through the git CLI, never programs.git, because the file holds
# per-machine identity and includeIf rules. Unlike it, this uses nix's git, so
# a Mac without the Xcode CLT never hits /usr/bin/git's install-prompt shim.
{ pkgs, lib, ... }:

let
  mkReconcile = import ./lib/reconcile.nix { inherit pkgs lib; };
in
{
  home.activation.gitGlobalConfig = mkReconcile {
    name = "git-global-config";
    path = [ pkgs.git ];
    text = ''
      # rerere replays a recorded resolution when the same conflict recurs,
      # as on repeated worktree rebases. rerere.autoUpdate stays off, so a
      # replayed resolution is left unstaged for review.
      if [ "$(git config --global --get rerere.enabled || true)" != true ]; then
        git config --global rerere.enabled true ||
          echo "git-global-config: could not set rerere.enabled" >&2
      fi
    '';
  };
}
