{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];

  nixpkgs = {
    config = {
    allowUnfree = true;
    cudaSupport = true;
  };
    system = "x86_64-linux";
  };

  networking = {
    hostName = "mason";
    networkmanager.enable = true;
  };

  boot = {
    loader.grub.enable = true;
    loader.grub.device = "/dev/nvme0n1";
    loader.grub.useOSProber = true;
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = [
      "nct6775" # motherboard fans and sensors
      "nvidia_uvm" # required for NVENC/CUDA user-space access
    ];
  };

  swapDevices = [{
    device = "/swapfile";
    size = 32 * 1024; # 32 GiB
  }];

  hardware.sc0710 = {
    enable = true;
    enableFirmware = true;
  };

  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
      desktopManager.xfce.enable = true;
    };
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;
    printing.enable = true;
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };

  users.users."masons" = {
    isNormalUser = true;
    description = "Mason Shaffer";
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  programs.firefox.enable = false;

  environment.systemPackages = with pkgs; [
    git
    discord
    steam
    code-cursor
    gsmartcontrol
    coolercontrol.coolercontrol-gui
    obs-studio
    lm_sensors
    proton-vpn
  ];

  system.stateVersion = "26.05";
}
