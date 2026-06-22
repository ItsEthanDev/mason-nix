{pkgs, ...}: let
  xfce4-indicator-plugin = pkgs.callPackage ../../../packages/xfce4-indicator-plugin.nix {};
in {
  imports = [
    ./hardware-configuration.nix
    ./storage.nix
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

  # 1Password desktop app + CLI for interactive/personal use. The headless
  # snapraid notification secrets are handled separately via opnix
  # (service-account driven); see storage.nix.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["masons"];
  };

  environment.systemPackages = with pkgs; [
    git
    discord
    steam
    code-cursor
    gsmartcontrol
    coolercontrol.coolercontrol-gui
    obs-studio
    ffmpeg-full
    lm_sensors
    proton-vpn
    xfce4-panel-profiles
    xfce4-whiskermenu-plugin
    xfce4-indicator-plugin
    networkmanagerapplet
    xfce4-pulseaudio-plugin       # volume / tray audio button
    xfce4-weather-plugin          # weather (themed by Redmond97)
    xfce4-systemload-plugin       # CPU graph
    xfce4-cpugraph-plugin         # another CPU monitor
    xfce4-netload-plugin          # network graph
    xfce4-clipman-plugin          # clipboard manager
    xfce4-docklike-plugin         # dock-style taskbar
    xfce4-notes-plugin            # sticky notes
    xfce4-genmon-plugin           # custom script output on panel
  ];

  services.conky.enable = true;

  programs.mpv.enable = true;
  programs.finamp.enable = true;
  programs.anki.enable = true;
  programs.kitty.enable = true;

  system.stateVersion = "26.05";
}
