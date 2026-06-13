{...}: {
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true; # required for Wayland; helps compositor frame pacing
    powerManagement.enable = true;
  };
}
