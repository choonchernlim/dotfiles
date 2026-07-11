# gcloud feature module: shell wiring + declarative config/components for the
# gcloud-cli brew cask (the cask itself is declared in the homebrew bundles).
# Selected per-host via hosts/*.nix home imports.
{ lib, ... }:

{
  # gcloud is installed by the gcloud-cli cask; nix owns its configuration:
  # usage reporting off (the Ansible task's *intent* - its code did the
  # opposite), beta component present, drifted alpha component removed.
  home.activation.gcloudSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # The Ansible gcloud role's shell snippet is replaced by zshrc wiring below.
    rm -f "$HOME/.zshrc_conf/gcloud.sh" || true

    _gcloud=/opt/homebrew/bin/gcloud
    if [ -x "$_gcloud" ]; then
      [ "$("$_gcloud" config get disable_usage_reporting 2>/dev/null)" = "True" ] || \
        "$_gcloud" config set disable_usage_reporting true 2>/dev/null || true
      _comps=$("$_gcloud" components list --only-local-state --format="value(id)" 2>/dev/null) || true
      echo "$_comps" | grep -qx "beta" || \
        "$_gcloud" components install beta --quiet 2>/dev/null || true
      echo "$_comps" | grep -qx "alpha" && \
        "$_gcloud" components remove alpha --quiet 2>/dev/null || true
    fi
  '';

  # Ordered before the shell module's main block (1000) to keep gcloud on PATH
  # ahead of the ~/.zshrc_conf snippet loop.
  programs.zsh.initContent = lib.mkOrder 900 ''
    # gcloud PATH + completions from the gcloud-cli cask ("latest" is a
    # stable symlink across upgrades). Replaces Ansible's gcloud.sh snippet.
    # completion.zsh.inc costs ~1s, so it is lazy-loaded on the first
    # tab-complete of gcloud/gsutil/bq instead of at every shell startup.
    _gcloud_sdk="/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk"
    [ -r "$_gcloud_sdk/path.zsh.inc" ] && source "$_gcloud_sdk/path.zsh.inc"
    if [ -r "$_gcloud_sdk/completion.zsh.inc" ]; then
      _lazy_gcloud_completion() {
        unfunction _lazy_gcloud_completion
        source "$_gcloud_sdk/completion.zsh.inc"
        # Re-dispatch so the tab-press that triggered the load still completes.
        "''${_comps[gcloud]:-_default}"
      }
      compdef _lazy_gcloud_completion gcloud gsutil bq
    fi
  '';
}
