{
  description = "System configuration flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    sc0710.url = "github:Nakildias/sc0710";
    zen-browser.url = "github:youwen5/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {nixpkgs, sc0710, zen-browser, ...}: {
    nixosConfigurations = {
      mason = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit zen-browser;};
        modules = [
          sc0710.nixosModules.default
          ./systems/x86_64-linux/mason
          ./modules/nixos/locale
          ./modules/nixos/nvidia
          ./modules/nixos/steam
          ./modules/nixos/waydroid
          ./modules/nixos/coolercontrol
          ./modules/nixos/mpc-qt
          ./modules/nixos/obs
          ./modules/nixos/redmond97-se
          ./modules/nixos/zen-browser
        ];
      };
    };
  };
}
