_: {
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];

  nixpkgs = {
    config.allowUnfree = true;
    system = "x86_64-linux";
  };

  networking.hostName = "mason";
}
