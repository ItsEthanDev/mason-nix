{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.finamp.enable = lib.mkEnableOption "Finamp Jellyfin music client";

  config = lib.mkIf config.programs.finamp.enable {
    environment.systemPackages = [pkgs.finamp];
  };
}
