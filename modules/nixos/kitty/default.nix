{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.kitty;

  gtkThemeColorsLib = builtins.readFile ../gtk-theme-colors-lib.sh;

  genKittyColors = pkgs.writeShellScript "kitty-gen-colors" ''
    set -eu
    ${gtkThemeColorsLib}
    ${builtins.readFile ./gen-kitty-colors.sh}
  '';

  kittyFonts = pkgs.runCommand "kitty-spacemono-fonts" {} ''
    mkdir -p $out/share/fonts/truetype
    cp ${pkgs.google-fonts}/share/fonts/truetype/SpaceMono*.ttf $out/share/fonts/truetype/
  '';

  kittyConf = pkgs.writeText "kitty.conf" ''
    # Managed by NixOS (programs.kitty). Override in kitty.local.conf.
    geninclude gen-colors.sh

    font_family      ${cfg.fontFamily}
    font_size        ${toString cfg.fontSize}
    confirm_os_window_close 0
    window_padding_width 4
    shell_integration enabled

    include kitty.local.conf
  '';

  setDefaultTerminal =
    lib.optionalString cfg.defaultTerminal ''
      xfconf-query -c xfce4-settings -p /default-terminal-emulator -s kitty.desktop 2>/dev/null || true
    '';

  startThemeWatcher =
    lib.optionalString cfg.syncTheme (builtins.readFile ./kitty-theme-watch.sh);

  kittySessionInit = pkgs.writeShellScript "kitty-session-init" (
    lib.replaceStrings
      ["@SET_DEFAULT_TERMINAL@" "@START_THEME_WATCHER@"]
      [setDefaultTerminal startThemeWatcher]
      (builtins.readFile ./kitty-session-init.sh)
  );

  linkKittyConfig = name: user: ''
    kittyDir="${user.home}/.config/kitty"
    localConf="$kittyDir/kitty.local.conf"
    mkdir -p "$kittyDir"
    ln -sfn ${genKittyColors} "$kittyDir/gen-colors.sh"
    ln -sfn ${kittyConf} "$kittyDir/kitty.conf"
    if [ ! -e "$localConf" ]; then
      : > "$localConf"
      chown ${name}:${user.group} "$localConf"
    fi
  '';
in {
  options.programs.kitty = {
    enable = lib.mkEnableOption "kitty terminal emulator with GTK theme sync";

    defaultTerminal = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set kitty as the XFCE default terminal emulator at login.";
    };

    fontFamily = lib.mkOption {
      type = lib.types.str;
      default = "Space Mono";
      description = "Primary monospace font family for kitty.";
    };

    fontSize = lib.mkOption {
      type = lib.types.float;
      default = 11.0;
      description = "Font size in points.";
    };

    syncTheme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Reload kitty when the active GTK theme changes.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      kitty
      xfce.xfconf
    ];

    fonts.packages = [kittyFonts];

    environment.etc."xdg/autostart/kitty-session-init.desktop".text =
      lib.optionalString (cfg.syncTheme || cfg.defaultTerminal) ''
      [Desktop Entry]
      Type=Application
      Name=Kitty session setup
      Comment=Default terminal and GTK theme sync for kitty
      Exec=${kittySessionInit}
      Terminal=false
      Hidden=false
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=XFCE;
    '';

    system.activationScripts.kitty = lib.stringAfter ["users"] (
      lib.concatStrings (
        lib.mapAttrsToList (
          name: user:
            lib.optionalString user.isNormalUser ''
              ${linkKittyConfig name user}
            ''
        ) config.users.users
      )
    );
  };
}
