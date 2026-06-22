{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.fastfetch.enable = lib.mkEnableOption "fastfetch system information tool";

  config = lib.mkIf config.programs.fastfetch.enable {
    environment.systemPackages = [pkgs.fastfetch];
  };
}
