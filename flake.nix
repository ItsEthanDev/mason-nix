{
  description = "System configuration flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    sc0710.url = "github:Nakildias/sc0710";
    zen-browser.url = "github:youwen5/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    # 1Password-backed secrets for NixOS (service-account driven).
    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {nixpkgs, sc0710, zen-browser, opnix, ...}: {
    nixosConfigurations = {
      mason = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit zen-browser;};
        modules = [
          sc0710.nixosModules.default
          opnix.nixosModules.default
          # Expose the opnix CLI (`opnix token set`) as pkgs.opnix.
          {nixpkgs.overlays = [opnix.overlays.default];}
          ./systems/x86_64-linux/mason
          ./modules/nixos/locale
          ./modules/nixos/input-method
          ./modules/nixos/locale-toggle
          ./modules/nixos/nvidia
          ./modules/nixos/steam
          ./modules/nixos/waydroid
          ./modules/nixos/coolercontrol
          ./modules/nixos/mpc-qt
          ./modules/nixos/obs
          ./modules/nixos/zen-browser
          ./modules/nixos/redmond97-se
          ./modules/nixos/conky
          ./modules/nixos/snapraid-btrfs
          ./modules/nixos/jellyfin
          ./modules/nixos/samba-media
        ];
      };
    };
  };
}
