{
  description = "dotfiles";

  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
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
      # Derive the login from the environment (impure) so no username is committed.
      # Under `sudo darwin-rebuild`, USER is "root" but sudo always exports SUDO_USER
      # as the real invoker; fall back to USER for non-sudo use (e.g. nix flake check).
      user =
        let
          s = builtins.getEnv "SUDO_USER";
        in
        if s != "" then s else builtins.getEnv "USER";

      # Hardcoded to the host machine architecture. Multi-arch is YAGNI for a personal dotfiles repo.
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      mkHost =
        name:
        let
          host = import ./hosts/${name}.nix;
        in
        assert nixpkgs.lib.assertMsg (user != "")
          "Could not determine username from $SUDO_USER or $USER - run via rebuild.sh, or set USER, and use --impure.";
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit user;
            profile = name;
          };
          modules = [
            { nixpkgs.hostPlatform = host.system; }
            ./modules/darwin
            host.darwin # profile-specific system config (homebrew bundle + quicklook)
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
                # Core home config + the feature modules this host selected
                # (same per-host bundle pattern as homebrew).
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
      darwinConfigurations = {
        work = mkHost "work";
        personal = mkHost "personal";
      };

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
              packageOverrides.treefmt = treefmtEval.config.build.wrapper; # use our treefmt config
            };
            statix.enable = true; # check-only anti-pattern lint (no auto-rewrite)
            deadnix.enable = true; # check-only dead-code lint (no --edit)
          };
        };
      };

      # `nix develop` enters this shell and installs .git/hooks/pre-commit via shellHook.
      devShells.${system}.default = pkgs.mkShell {
        shellHook = self.checks.${system}.pre-commit.shellHook;
        buildInputs = self.checks.${system}.pre-commit.enabledPackages;
      };
    };
}
