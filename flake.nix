{
  description = "Ben's machines: the same editor, shell and terminal setup everywhere";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs"; # one nixpkgs for everything
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      # A machine = the shared setup in common/home + its own systems/<host>/home.nix
      machine = system: hostModule:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./common/home hostModule ];
        };
    in
    {
      # Named "user@hostname", so `home-manager switch --flake .` picks the right one
      homeConfigurations = {
        "benk@benk-studio" = machine "aarch64-darwin" ./systems/benk-studio/home.nix; # work Mac Studio
        # The Linux PC and personal Mac go here, e.g.
        # "ben@arch" = machine "x86_64-linux" ./systems/arch/home.nix;
      };
    };
}
