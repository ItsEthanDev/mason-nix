{
  description = "System configuration flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    sc0710.url = "github:Nakildias/sc0710";
  };

  outputs = {nixpkgs, sc0710, ...}: {
    nixosConfigurations = {
      mason = nixpkgs.lib.nixosSystem {
        modules = [
          sc0710.nixosModules.default
          ./systems/x86_64-linux/mason
          ./modules/nixos/locale
          ./modules/nixos/nvidia
          ./modules/nixos/steam
          ./modules/nixos/waydroid
          ./modules/nixos/coolercontrol
        ];
      };
    };
  };
}
