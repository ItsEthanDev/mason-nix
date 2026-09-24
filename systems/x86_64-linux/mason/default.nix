{pkgs, ...}: let
  xfce4-indicator-plugin = pkgs.callPackage ../../../packages/xfce4-indicator-plugin.nix {};

  # Nix-packaged interpreters do not consume NIX_LD_LIBRARY_PATH when loading
  # native modules, so expose the C++ runtime directly to Bun and its children.
  # https://github.com/nix-community/nix-ld#my-pythonnodejsrubyinterpreter-libraries-do-not-find-the-libraries-configured-by-nix-ld
  bunWithNativeLibraries = pkgs.writeShellScriptBin "bun" ''
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [pkgs.stdenv.cc.cc]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${pkgs.bun}/bin/bun "$@"
  '';
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
    overlays = [
      (_final: prev: {
        whisper-cpp = prev.whisper-cpp.override {
          cudaSupport = false;
        };

        opencode = prev.opencode.overrideAttrs (finalAttrs: oldAttrs: {
          version = "1.18.32";
          src = prev.fetchFromGitHub {
            owner = "anomalyco";
            repo = "opencode";
            tag = "v${finalAttrs.version}";
            hash = "sha256-h5AmK9R0Clk+LT0Tmmfg7iXa6dXNlPi2I5xCjTDRdcg=";
          };
          passthru =
            oldAttrs.passthru
            // {
              node_modules = oldAttrs.passthru.node_modules.overrideAttrs (_: {
                inherit (finalAttrs) version src;
                outputHash = "sha256-yHhVrJJnzp2gzlLoe0W78VCdvjpQ3zW+PmnFE6TwCFc=";
              });
            };
        });
      })
    ];

    config = {
      allowUnfree = true;
      # Leave cudaSupport off. The unversioned cudaPackages on this
      # nixos-unstable is 12.9; NVCC's documented host compiler max is
      # GCC 14, while stdenv is GCC 15.3. Even backendStdenv (GCC 14.4)
      # still dies in cuda_device_runtime_api.h. That rebuilds opencv,
      # frei0r, ffmpeg-full, and jellyfin-ffmpeg from source.
      # NVENC/NVDEC use the NVIDIA driver + nv-codec-headers, which
      # ffmpeg-full and Jellyfin already get from allowUnfree.
    };
    system = "x86_64-linux";
  };

  networking = {
    hostName = "mason";
    networkmanager = {
      enable = true;
      wifi.powersave = false;
    };
  };

  boot = {
    loader.grub.enable = true;
    loader.grub.device = "/dev/nvme0n1";
    loader.grub.useOSProber = true;
    loader.grub.memtest86.enable = true;
    # 7.2.3 + NVIDIA open modules corrupted PTEs (app crashes, freezes).
    # Last known-good boot was 7.0.11; 7.0 is EOL in this nixpkgs.
    kernelPackages = pkgs.linuxPackages_7_1;
    kernelModules = [
      "nct6775" # motherboard fans and sensors
      "nvidia_uvm" # required for NVENC/CUDA user-space access
      "sg" # SCSI generic access required by MakeMKV
    ];
  };

  swapDevices = [{
    device = "/swapfile";
    size = 32 * 1024; # 32 GiB
  }];

  hardware.sc0710 = {
    enable = true;
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

  # PipeWire logs RTKit ServiceUnknown; without it, audio can underrun
  # and sound like a scratched record even when the network is fine.
  security.rtkit.enable = true;

  users.users."masons" = {
    isNormalUser = true;
    description = "Mason Shaffer";
    extraGroups = ["networkmanager" "wheel" "dialout" "cdrom"];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  programs.firefox.enable = false;
  programs.retroarch.enable = true;
  programs.dconf.enable = true;

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
    easyeffects
    qpwgraph
    rawtherapee
    opencode
    arduino-ide
    makemkv
    vlc
    handbrake
    bun
    nodejs
    gcc
    vial
    herdr
    hunk
    teams-for-linux
    (blender.override {
      cudaSupport = true;
      cudaArches = ["sm_75"]; # Turing (RTX 2070)
      openUsdSupport = false;
    })
  ];

  services.conky.enable = true;

  programs.mpv.enable = true;
  programs.finamp.enable = true;
  programs.anki.enable = true;
  programs.kitty.enable = true;
  programs.ghostty.enable = true;
  programs.crt-wrapper.enable = true;
  programs.neovim.enable = true;
  programs.cool-retro-term.enable = true;
  programs.fastfetch.enable = true;
  programs.chafa.enable = true;

  system.stateVersion = "26.05";
}
