{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.mpv;

  mpv360 = pkgs.callPackage ../../../packages/mpv360.nix {};

  mpvPackage = pkgs.mpv.override {
    mpv-unwrapped = pkgs.mpv-unwrapped.override {
      ffmpeg = pkgs.ffmpeg-full;
    };
  };

  mpvConf = pkgs.writeText "mpv.conf" ''
    # Managed by NixOS (programs.mpv). Override in ~/.config/mpv/mpv.local.conf.
    profile=gpu-hq
    hwdec=auto-safe
    ytdl-format=bestvideo+bestaudio/best
    demuxer-max-bytes=400MiB
    save-position-on-quit=yes
    include=${cfg.localConfPath}
  '';

  linkMpvConfig = name: user: ''
    mpvDir="${user.home}/.config/mpv"
    localConf="$mpvDir/mpv.local.conf"
    mkdir -p "$mpvDir"/scripts "$mpvDir"/shaders "$mpvDir"/script-opts
    ln -sfn ${mpv360}/scripts/mpv360.lua "$mpvDir/scripts/mpv360.lua"
    ln -sfn ${mpv360}/shaders/mpv360.glsl "$mpvDir/shaders/mpv360.glsl"
    ln -sfn ${mpv360}/script-opts/mpv360.conf "$mpvDir/script-opts/mpv360.conf"
    ln -sfn ${mpvConf} "$mpvDir/mpv.conf"
    if [ ! -e "$localConf" ]; then
      : > "$localConf"
      chown ${name}:${user.group} "$localConf"
    fi
  '';
in {
  options.programs.mpv = {
    enable = lib.mkEnableOption "mpv media player with mpv360 for 360° video";

    localConfPath = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/mpv/mpv.local.conf";
      description = ''
        Path included at the end of the managed mpv.conf for user overrides.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [mpvPackage];

    system.activationScripts.mpv = lib.stringAfter ["users"] (
      lib.concatStrings (
        lib.mapAttrsToList (
          name: user:
            lib.optionalString user.isNormalUser ''
              ${linkMpvConfig name user}
            ''
        ) config.users.users
      )
    );
  };
}
