{
  description = "dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nix-darwin,
      nix-homebrew,
      home-manager,
      nixpkgs,
      treefmt-nix,
      git-hooks,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Derive the login from the environment (impure) so no username is committed.
      # Under `sudo darwin-rebuild`, USER is "root" but sudo exports SUDO_USER as
      # the real invoker; fall back to USER for non-sudo use (e.g. nix flake check).
      user =
        let
          s = builtins.getEnv "SUDO_USER";
        in
        if s != "" then s else builtins.getEnv "USER";

      # Architecture of every machine this repo targets (per-host override in hosts/*.nix).
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      # One profile per hosts/<name>.nix - the same discovery rebuild.sh does.
      hostNames = map (lib.removeSuffix ".nix") (
        builtins.attrNames (
          lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir ./hosts)
        )
      );

      mkHost =
        name:
        let
          host = import ./hosts/${name}.nix;
        in
        assert lib.assertMsg (user != "")
          "Could not determine username from $SUDO_USER or $USER - run via rebuild.sh, or set USER, and use --impure.";
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit user;
            profile = name;
          };
          modules = [
            { nixpkgs.hostPlatform = host.system; }
            ./modules/darwin
            host.darwin # homebrew bundles + darwin feature modules this host gets
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-bak";
                extraSpecialArgs = {
                  inherit user;
                  profile = name;
                };
                # Core home config + the home feature modules this host gets.
                users.${user}.imports = [
                  ./modules/home
                  (host.home or { })
                ];
              };
            }
          ];
        };
    in
    {
      darwinConfigurations = lib.genAttrs hostNames mkHost;

      # bootstrap.sh runs the first switch through this so it uses the darwin-rebuild
      # pinned in flake.lock, not whatever the release branch points at that day.
      packages.${system}.darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;

      # nix fmt - formats all .nix files via nixfmt
      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system} = {
        # nix build .#checks.aarch64-darwin.formatting - fails if any file is not formatted
        formatting = treefmtEval.config.build.check self;
        # nix build .#checks.aarch64-darwin.pre-commit - builds the git hook derivation;
        # `nix develop` installs it into .git/hooks/pre-commit with hermetic Nix store paths.
        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            treefmt = {
              enable = true;
              packageOverrides.treefmt = treefmtEval.config.build.wrapper;
            };
            # Fails when a backticked path in AGENTS.md no longer exists. It shells out to
            # `git check-ignore`, so it needs a working tree and cannot be a runCommand check.
            agents-md-paths = {
              enable = true;
              name = "agents-md-paths";
              entry = "${pkgs.python3}/bin/python3 scripts/test_agents_md.py";
              files = "^AGENTS\\.md$";
              pass_filenames = false;
            };
            statix.enable = true; # check-only anti-pattern lint (no auto-rewrite)
            deadnix.enable = true; # check-only dead-code lint (no --edit)
            shellcheck = {
              enable = true; # rebuild.sh, bootstrap.sh, sync-skills.sh, scripts/*.sh
              # Neither is a standalone script: cache-purge.sh is a shebang-less fragment
              # that writeShellApplication wraps and already shellchecks at build time
              # (modules/home/cachepurge); .envrc is direnv's dialect (`use flake`).
              excludes = [
                "cache-purge\\.sh$"
                "^\\.envrc$"
              ];
            };
          };
        };
        # nix build .#checks.aarch64-darwin.rebuild-format - replays captured `rebuild`
        # streams through scripts/rebuild-format.sh and diffs against the golden files.
        # `rebuild` itself must never be run by an agent, so this is what proves the
        # formatter. Runs under nix's bash 5; bash 3.2 (macOS /bin/bash) compatibility
        # is a script constraint checked by hand.
        rebuild-format = pkgs.runCommand "rebuild-format-golden" { nativeBuildInputs = [ pkgs.bash ]; } ''
          export HOME=/Users/tester REBUILD_FORMAT_TIMES=0
          for n in sample edge; do
            bash ${./scripts/rebuild-format.sh} < ${./scripts/fixtures}/rebuild-$n.log > $n.out
            diff -u ${./scripts/fixtures}/rebuild-$n.expected $n.out || {
              echo "rebuild-$n: output drifted from the golden file. If intended, regenerate:" >&2
              echo "  HOME=/Users/tester REBUILD_FORMAT_TIMES=0 bash scripts/rebuild-format.sh < scripts/fixtures/rebuild-$n.log > scripts/fixtures/rebuild-$n.expected" >&2
              exit 1
            }
          done
          touch $out
        '';
        # Claude Code and Codex must run the same hooks (both call scripts/format-hook.sh);
        # drift between the two blocks fails evaluation, so --no-build catches it too.
        agent-hooks =
          assert lib.assertMsg (
            (lib.importJSON ./.claude/settings.json).hooks == (lib.importJSON ./.codex/hooks.json).hooks
          ) ".claude/settings.json and .codex/hooks.json must declare identical hooks";
          pkgs.emptyFile;
      }
      # host-<name>: every profile's system closure, so `nix flake check --impure --no-build`
      # evaluates all of them from any machine and a broken hosts/<name>.nix is caught
      # before that machine rebuilds. (Without --no-build these build the full systems.)
      // lib.mapAttrs' (name: cfg: lib.nameValuePair "host-${name}" cfg.system) self.darwinConfigurations;

      # `nix develop` enters this shell and installs .git/hooks/pre-commit via shellHook.
      devShells.${system}.default = pkgs.mkShell {
        shellHook = self.checks.${system}.pre-commit.shellHook;
        buildInputs = self.checks.${system}.pre-commit.enabledPackages;
      };
    };
}
