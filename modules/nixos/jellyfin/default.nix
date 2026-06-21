{config, ...}: let
  poolMount = config.services.snapraid-btrfs.poolMount;
  mediaPath = "${poolMount}/media";
in {
  services.jellyfin = {
    enable = true;
    openFirewall = true;

    hardwareAcceleration = {
      enable = true;
      type = "nvenc";
      device = "/dev/dri/renderD128";
    };

    transcoding.enableHardwareEncoding = true;
    forceEncodingConfig = true;
  };

  systemd.services.jellyfin.serviceConfig = {
    ReadOnlyPaths = [mediaPath];
    SupplementaryGroups = ["video" "render" "media"];
  };

  users.users.jellyfin.extraGroups = ["video" "render" "media"];
  users.groups.media = {};
}
