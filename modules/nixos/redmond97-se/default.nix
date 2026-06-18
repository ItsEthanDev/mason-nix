{
  config,
  pkgs,
  lib,
  ...
}:
let
  redmond97-se = pkgs.callPackage ../../../pkgs/redmond97-se/package.nix {};
in {
  options.redmond97-se = {
    gtkTheme = lib.mkOption {
      type = lib.types.str;
      default = "Redmond97 SE Classic";
      description = "GTK/Xfwm4 theme variant (must match a name under share/themes).";
    };

    iconTheme = lib.mkOption {
      type = lib.types.str;
      default = "Obsidian-Pure";
      description = "Icon theme bundled with Redmond97 SE.";
    };
  };

  config = {
    environment.systemPackages = [redmond97-se];

    environment.sessionVariables = {
      GTK_THEME = config.redmond97-se.gtkTheme;
      GTK_OVERLAY_SCROLLING = "0";
      QT_QPA_PLATFORMTHEME = "gtk3";
      XCURSOR_THEME = config.redmond97-se.iconTheme;
    };
  };
}
