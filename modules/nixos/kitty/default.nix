{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.kitty.enable = lib.mkEnableOption "kitty terminal emulator";

  config = lib.mkIf config.programs.kitty.enable {
    environment.systemPackages = [pkgs.kitty];
  };
}
