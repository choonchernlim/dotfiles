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
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs }:
    let
      # Derive the login from the environment (impure) so no username is committed.
      # Under `sudo darwin-rebuild`, USER is "root" but sudo always exports SUDO_USER
      # as the real invoker; fall back to USER for non-sudo use (e.g. nix flake check).
      user = let s = builtins.getEnv "SUDO_USER"; in if s != "" then s else builtins.getEnv "USER";

      mkHost = name:
        let host = import ./hosts/${name}.nix;
        in
        assert nixpkgs.lib.assertMsg (user != "")
          "Could not determine username from $SUDO_USER or $USER - run via rebuild.sh, or set USER, and use --impure.";
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit user; profile = name; };
          modules = [
            { nixpkgs.hostPlatform = host.system; }
            ./modules/darwin
            host.darwin                     # profile-specific system config (empty for now)
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-bak";
              home-manager.extraSpecialArgs = { inherit user; profile = name; };
              home-manager.users.${user} = import ./modules/home;
            }
          ];
        };
    in
    {
      darwinConfigurations = {
        work = mkHost "work";
        personal = mkHost "personal";
      };
    };
}
