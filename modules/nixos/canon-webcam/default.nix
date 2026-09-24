{
  config,
  pkgs,
  ...
}: let
  entangleWithVirtualCamera = pkgs.entangle.overrideAttrs (old: {
    buildInputs =
      (old.buildInputs or [])
      ++ [pkgs.gst_all_1.gst-plugins-good];

    postInstall =
      (old.postInstall or "")
      + ''
        pluginDir="$out/lib/entangle/plugins/virtual_camera"
        install -Dm644 ${./virtual-camera.plugin} \
          "$pluginDir/virtual_camera.plugin"
        install -Dm644 ${./virtual_camera.py} \
          "$pluginDir/virtual_camera.py"
      '';
  });
in {
  programs.gphoto2.enable = true;

  environment.systemPackages = [
    entangleWithVirtualCamera
    pkgs.v4l-utils
  ];

  users.users.masons.extraGroups = ["camera" "video"];

  # OBS provisions /dev/video1 and loads v4l2loopback. Add Entangle's
  # independent output after the module is available.
  systemd.services.entangle-virtual-camera = {
    description = "Provision the Entangle virtual camera";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    path = [config.boot.kernelPackages.v4l2loopback.bin];
    script = ''
      if [[ ! -e /dev/video9 ]]; then
        v4l2loopback-ctl add \
          --name "Entangle Virtual Camera" \
          --exclusive-caps 1 \
          --buffers 2 \
          /dev/video9
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${config.boot.kernelPackages.v4l2loopback.bin}/bin/v4l2loopback-ctl delete /dev/video9";
    };
  };

  security.polkit.enable = true;
}
