{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.ghostty;

  # Free CG98 is an 8x16 pixel font, so it only renders perfectly -- square
  # pixels, uniform rows, symmetric cell margins, scanlines on pixel centers --
  # at integer pixel scales, i.e. when the em is a whole multiple of 16 px.
  # Ghostty sizes fonts as px = points * dpi / 72, and our em == units_per_em, so
  #   cell_height(px) = round(points * dpi / 72).
  # For an integer scale N (cell = 8N x 16N px) the required point size is
  #   points = 1152 * N / dpi   (== 12 * N at the XFCE default of 96 dpi).
  # If your display's effective dpi differs, change ghosttyDpi (verify with the
  # font-pixel debug shader); the step and default size below follow from it.
  ghosttyDpi = 96;
  ghosttyFontStep = 1152 / ghosttyDpi; # points per one integer pixel scale (12)
  ghosttyFontScale = 2; # default zoom: 2x -> cell 16x32 px (readable + crisp)
  ghosttyFontSize = ghosttyFontScale * ghosttyFontStep;

  # ctrl +/- granularity: subdivide the integer-scale step so there are more
  # intermediate sizes. Every ghosttyZoomSubdiv-th press lands exactly on a
  # pixel-perfect integer scale (square pixels, even rows); the steps between
  # are still aligned by the shaders' em uniforms but rasterize with slightly
  # uneven font-pixel rows.
  ghosttyZoomSubdiv = 4; # quarter-steps -> 3 pt per press at 96 dpi
  ghosttyZoomStep = ghosttyFontStep / ghosttyZoomSubdiv;

  ghosttyPkg = pkgs.ghostty.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ./patches/ghostty-cell-size-uniform.patch
    ];
  });

  freecg98Font = pkgs.stdenv.mkDerivation {
    pname = "freecg98";
    version = "local";
    src = ./fonts;
    nativeBuildInputs = [pkgs.fontforge];
    dontUnpack = true;

    # Build a scalable outline TTF (each pixel -> square contour) instead of an
    # embedded bitmap strike, so Ghostty's ctrl +/- font resizing scales it.
    buildPhase = ''
      fontforge -lang=py -script $src/make-outline-font.py $src/FREECG98.BMP FREECG98.ttf
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/fonts/truetype
      cp FREECG98.ttf $out/share/fonts/truetype/
      runHook postInstall
    '';
  };

  crtGeomShader = ./shaders/crt-geom.glsl;
  crtLottesShader = ./shaders/crt-lottes.glsl;
  crtRvmShader = ./shaders/crt-rvm.glsl;
  fontPixelRowCentersDebugShader = ./shaders/font-pixel-row-centers-debug.glsl;

  # Selectable custom shaders, keyed by the `programs.ghostty.shader` option.
  # All are aligned to the font-pixel grid (scanlines on the 16 rows, taps on
  # the 8 columns), so they track ctrl +/- zooming identically.
  shaderPaths = {
    crt-geom = crtGeomShader;
    crt-lottes = crtLottesShader;
    crt-rvm = crtRvmShader;
  };
  selectedShader = shaderPaths.${cfg.shader};
  shinonomeFont = pkgs.stdenvNoCC.mkDerivation {
    pname = "jf-dot-shinonome-min12";
    version = "local";
    src = ./fonts/JF-Dot-ShinonomeMin12.ttf;
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/fonts/truetype
      cp "$src" $out/share/fonts/truetype/JF-Dot-ShinonomeMin12.ttf
      runHook postInstall
    '';
  };

  pc9800Font = pkgs.stdenvNoCC.mkDerivation {
    pname = "pc-9800";
    version = "local";
    src = ./fonts/pc-9800.ttf;
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/fonts/truetype
      cp "$src" $out/share/fonts/truetype/pc-9800.ttf
      runHook postInstall
    '';
  };

  ghosttyConf = pkgs.writeText "ghostty-config" ''
    # Managed by NixOS (programs.ghostty). Override in ~/.config/ghostty/config.local.
    # Default shader chosen by `programs.ghostty.shader`; switch live (per-window)
    # with `ghostty-crt-tuner`, which also exposes every parameter as a slider.
    custom-shader = ${selectedShader}
    # custom-shader = ${fontPixelRowCentersDebugShader}
    custom-shader-animation = true
    resize-overlay = never

    # The CRT tuner reloads the config on every slider change (SIGUSR2), which
    # would otherwise spam the "Reloaded configuration" toast; suppress just that
    # notification (clipboard-copy notifications stay on).
    app-notifications = no-config-reload

    # Ghostty is built with libadwaita, which ignores third-party GTK themes for
    # client-side decorations. On XFCE, use xfwm4 (server-side) so Redmond97's
    # xfwm4 theme draws the titlebar and window borders.
    window-theme = system
    window-decoration = server
    gtk-titlebar = false
    gtk-wide-tabs = false
    gtk-toolbar-style = flat

    font-family = Free CG98
    font-size = ${toString ghosttyFontSize}
    freetype-load-flags = monochrome

    # Zoom in fixed sub-steps of the integer pixel scale (ghosttyZoomSubdiv per
    # full scale). reset returns to the configured font-size, an aligned scale.
    keybind = ctrl+equal=increase_font_size:${toString ghosttyZoomStep}
    keybind = ctrl+plus=increase_font_size:${toString ghosttyZoomStep}
    keybind = ctrl+minus=decrease_font_size:${toString ghosttyZoomStep}
    keybind = ctrl+zero=reset_font_size

    # Picks up gtk-custom-css for the active GTK theme (see ghostty wrapper).
    config-file = ~/.config/ghostty/autogen-gtk.conf
    config-file = ${cfg.localConfPath}

    # Live CRT tuning overrides written by `ghostty-crt-tuner`. Empty unless the
    # tuner is active; included last so it wins while you are tuning. Send the
    # running Ghostty SIGUSR2 (the tuner does this) to reload after it changes.
    config-file = ~/.config/ghostty/shader-tune.conf
  '';

  ghosttyLauncher = pkgs.writeShellScriptBin "ghostty" ''
    set -euo pipefail

    autogen="$HOME/.config/ghostty/autogen-gtk.conf"
    mkdir -p "$(dirname "$autogen")"

    theme=""
    if command -v ${pkgs.xfce.xfconf}/bin/xfconf-query >/dev/null 2>&1; then
      theme=$(${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
    elif command -v gsettings >/dev/null 2>&1; then
      theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'" || true)
    fi

    css=""
    if [ -n "$theme" ]; then
      export GTK_THEME="$theme"
      IFS=: read -r -a data_dirs <<< "''${XDG_DATA_DIRS:-/run/current-system/sw/share:/usr/share}"
      for dir in "''${data_dirs[@]}"; do
        candidate="$dir/themes/$theme/gtk-4.0/gtk.css"
        if [ -f "$candidate" ]; then
          css="$candidate"
          break
        fi
      done
    fi

    if [ -n "$css" ]; then
      cat > "$autogen" <<EOF
# Generated by NixOS from the active GTK theme: $theme
gtk-custom-css = "$css"
EOF
    else
      : > "$autogen"
    fi

    exec ${lib.getExe ghosttyPkg} "$@"
  '';

  # Live tuner GUI for the CRT shader parameters. See tools/ghostty-crt-tuner.py.
  # procps provides pkill (used to SIGUSR2 Ghostty for a config/shader reload).
  ghosttyTuner = pkgs.writeShellScriptBin "ghostty-crt-tuner" ''
    export PATH=${pkgs.procps}/bin:$PATH
    exec ${pkgs.python3.withPackages (ps: [ps.tkinter])}/bin/python3 \
      ${./tools/ghostty-crt-tuner.py} \
      --shader crt-geom=${crtGeomShader} \
      --shader crt-lottes=${crtLottesShader} \
      --shader crt-rvm=${crtRvmShader} \
      --default ${cfg.shader} "$@"
  '';

  linkGhosttyConfig = name: user: ''
    ghosttyDir="${user.home}/.config/ghostty"
    localConf="$ghosttyDir/config.local"
    autogenConf="$ghosttyDir/autogen-gtk.conf"
    tuneConf="$ghosttyDir/shader-tune.conf"
    mkdir -p "$ghosttyDir"
    # This activation runs as root, so the freshly created directory would be
    # root-owned and the user could not write live shader files into it.
    chown ${name}:${user.group} "$ghosttyDir"
    ln -sfn ${ghosttyConf} "$ghosttyDir/config"
    if [ ! -e "$localConf" ]; then
      : > "$localConf"
      chown ${name}:${user.group} "$localConf"
    fi
    if [ ! -e "$autogenConf" ]; then
      : > "$autogenConf"
      chown ${name}:${user.group} "$autogenConf"
    fi
    if [ ! -e "$tuneConf" ]; then
      : > "$tuneConf"
      chown ${name}:${user.group} "$tuneConf"
    fi
  '';
in {
  options.programs.ghostty = {
    enable = lib.mkEnableOption "ghostty terminal emulator with CRT-Geom shader";

    shader = lib.mkOption {
      type = lib.types.enum ["crt-geom" "crt-lottes" "crt-rvm"];
      default = "crt-geom";
      description = ''
        Which font-pixel-aligned CRT custom shader to load by default. All can
        be switched live (and fully tuned) at runtime with `ghostty-crt-tuner`.
      '';
    };

    localConfPath = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/ghostty/config.local";
      description = ''
        Path included at the end of the managed ghostty config for user overrides.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = [pc9800Font freecg98Font shinonomeFont];

    environment.systemPackages = [
      ghosttyLauncher
      ghosttyTuner
      ghosttyPkg.terminfo
    ];

    system.activationScripts.ghostty = lib.stringAfter ["users"] (
      lib.concatStrings (
        lib.mapAttrsToList (
          name: user:
            lib.optionalString user.isNormalUser ''
              ${linkGhosttyConfig name user}
            ''
        ) config.users.users
      )
    );
  };
}
