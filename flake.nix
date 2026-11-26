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
      # Every machine gets the same setup (common/home); only the CPU/OS and
      # the username differ
      machine = system: user:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./common/home { home.username = user; } ];
        };
    in
    {
      # home-manager switch --flake ~/dotfiles#mac   (or #linux)
      homeConfigurations = {
        mac = machine "aarch64-darwin" "benk";
        linux = machine "x86_64-linux" "benk";
      };
    };
}
