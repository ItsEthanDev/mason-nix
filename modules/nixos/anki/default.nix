{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.anki;

  ankiPackage =
    if cfg.addons == [] then
      cfg.package
    else
      cfg.package.withAddons cfg.addons;
in {
  options.programs.anki = {
    enable = lib.mkEnableOption "Anki spaced repetition flashcard program";

    package = lib.mkPackageOption pkgs "anki" {
      example = "pkgs.anki-bin";
    };

    addons = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[ pkgs.ankiAddons.passfail2 ]";
      description = ''
        Anki add-ons to install declaratively via
        {option}`programs.anki.package`.withAddons`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ankiPackage];
  };
}
