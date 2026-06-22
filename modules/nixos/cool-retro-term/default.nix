{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.cool-retro-term.enable = lib.mkEnableOption "cool-retro-term terminal emulator";

  config = lib.mkIf config.programs.cool-retro-term.enable {
    environment.systemPackages = [pkgs.cool-retro-term];
  };
}
