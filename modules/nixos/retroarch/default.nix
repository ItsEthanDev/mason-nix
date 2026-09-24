{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.retroarch.enable = lib.mkEnableOption "RetroArch frontend with all available cores";

  config = lib.mkIf config.programs.retroarch.enable {
    environment.systemPackages = [pkgs.retroarch-full];
  };
}
