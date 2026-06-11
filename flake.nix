{
  description = "System configuration flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {nixpkgs, ...}: {
    nixosConfigurations = {
      mason = nixpkgs.lib.nixosSystem {
        modules = [
          ./systems/x86_64-linux/mason
          ./modules/nixos/locale
        ];
      };
    };
  };
}
