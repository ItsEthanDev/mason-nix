{config, ...}: {
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true; # required for Wayland; helps compositor frame pacing
    # Turing (RTX 2070): open modules require GSP firmware. GSP + nvidia-smi
    # polling (conky/coolercontrol) hung the RM in ioctl and froze the box
    # (soft lockups in .coolercontrold / nvidia-smi). Proprietary can run
    # without GSP. Open modules cannot (assertion: open -> gsp.enable).
    open = false;
    gsp.enable = false;
    # Desktop card; runtime PM is a known freeze source with nvidia-smi.
    powerManagement.enable = false;
    # Keep RM initialized so conky's 10s nvidia-smi polls do not reinit.
    nvidiaPersistenced = true;
    nvidiaSettings = true;
    # 610.x was the last stable driver here (610.43.02 on kernel 7.0.11).
    # nvidiaPackages.stable is 595.99.02, which with kernel 7.2 corrupted
    # page tables (steamwebhelper Oops, Jellyfin SEGV, system freezes).
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    # nixpkgs#465310: gsp.enable = false only skips firmware files; it does
    # not set NVreg_EnableGpuFirmware=0, so GSP stays on without this.
    moduleParams.nvidia.NVreg_EnableGpuFirmware = 0;
  };
}
