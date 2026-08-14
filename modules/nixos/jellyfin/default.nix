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

    # NVENC/CUDA needs the NVIDIA char devices, but the upstream module only
    # whitelists hardwareAcceleration.device (the DRI render node). With
    # DevicePolicy=auto, any DeviceAllow entry turns access into a strict
    # allow-list, so /dev/nvidia* are blocked and h264_nvenc dies with code 187.
    DeviceAllow = [
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
    ];
  };

  users.users.jellyfin.extraGroups = ["video" "render" "media"];
  users.groups.media = {};
}
