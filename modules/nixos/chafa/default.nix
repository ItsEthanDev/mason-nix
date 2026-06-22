{
  config,
  lib,
  pkgs,
  ...
}: {
  options.programs.chafa.enable = lib.mkEnableOption "chafa terminal graphics";

  config = lib.mkIf config.programs.chafa.enable {
    environment.systemPackages = [pkgs.chafa];
  };
}
