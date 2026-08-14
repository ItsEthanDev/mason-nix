{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.crt-wrapper;

  # Picom's shader ABI supplies the window texture and its dimensions, but no
  # application-specific source-pixel geometry. Feed CRT-RVM a synthetic 8x16
  # cell so its reconstruction grid has a stable, configurable screen-pixel
  # pitch. The values below mirror the active crt-rvm state saved by Ghostty's
  # tuner; the repository shader remains the canonical implementation.
  picomShader = pkgs.runCommand "crt-rvm-picom.glsl" {} ''
    cat >"$out" <<'EOF'
    #version 330

    in vec2 texcoord;
    uniform sampler2D tex;
    uniform vec2 effective_size;
    uniform float time;

    vec4 default_post_processing(vec4 color);

    #define iChannel0 tex
    #define iResolution vec3(effective_size, 1.0)
    #define iCellSize vec4(CRT_PIXEL_PITCH * 8.0, CRT_PIXEL_PITCH * 16.0, 0.0, CRT_PIXEL_PITCH * 16.0)
    #define iGridPadding vec4(0.0)
    #define iFrame (time * 0.06)
    #define CRT_PIXEL_PITCH ${toString cfg.pixelPitch}
    EOF

    cat ${../ghostty/shaders/crt-rvm.glsl} >>"$out"

    cat >>"$out" <<'EOF'

    vec4 window_shader() {
      vec4 color;
      mainImage(color, texcoord);
      return default_post_processing(color);
    }
    EOF

    substituteInPlace "$out" \
      --replace-fail "#define RVM_MODE 0" "#define RVM_MODE 2" \
      --replace-fail "#define HARDPIX -3.0" "#define HARDPIX -2.5" \
      --replace-fail "#define WARPX 0.01563" "#define WARPX 0.04" \
      --replace-fail "#define WARPY 0.04167" "#define WARPY 0.04" \
      --replace-fail "#define RVM_SCAN_DARK 2.4" "#define RVM_SCAN_DARK 1.0" \
      --replace-fail "#define RVM_SCAN_BRIGHT 1.1" "#define RVM_SCAN_BRIGHT 0.9" \
      --replace-fail "#define RVM_RECON_SOFT -2.0" "#define RVM_RECON_SOFT -4.8" \
      --replace-fail "#define RVM_SCAN_HARD -8.0" "#define RVM_SCAN_HARD -3.0" \
      --replace-fail "#define RVM_DARK 0.875" "#define RVM_DARK 1.0" \
      --replace-fail "#define MASKSIZE 6.0" "#define MASKSIZE 3.0" \
      --replace-fail "#define BRIGHTBOOST 1.0" "#define BRIGHTBOOST 0.5"
  '';

  crtWrap = pkgs.writeShellApplication {
    name = "crt-wrap";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      xdotool
      xprop
    ];
    text = builtins.readFile ./crt-wrap.sh;
  };

  crtWindowTuner = pkgs.writeShellScriptBin "crt-window-tuner" ''
    export PATH=${lib.makeBinPath [pkgs.procps pkgs.xdotool pkgs.xprop]}:$PATH
    exec ${pkgs.python3.withPackages (pythonPackages: [pythonPackages.tkinter])}/bin/python3 \
      ${./crt-window-tuner.py} --template ${picomShader} "$@"
  '';

  startPicom = pkgs.writeShellScriptBin "crt-picom" ''
    set -euo pipefail

    config_dir="$HOME/.config/crt-wrapper"
    shader="$config_dir/live.glsl"
    template_marker="$config_dir/template-path"
    runtime_config="$config_dir/picom.conf"
    ${pkgs.coreutils}/bin/mkdir -p "$config_dir"

    # Preserve tuning across sessions, but refresh when the managed template
    # changes (for example, when switching from CRT-Geom to CRT-RVM).
    current_template=""
    if [ -e "$template_marker" ]; then
      current_template="$(${pkgs.coreutils}/bin/cat "$template_marker")"
    fi
    if [ ! -e "$shader" ] || [ "$current_template" != "${picomShader}" ]; then
      ${pkgs.coreutils}/bin/install -m 0644 ${picomShader} "$shader"
      printf '%s\n' ${picomShader} >"$template_marker"
    fi

    temporary="$runtime_config.tmp"
    cat >"$temporary" <<EOF
    backend = "glx";
    vsync = true;
    use-damage = true;
    xrender-sync-fence = true;
    detect-client-opacity = true;

    rules = (
      {
        match = "_CRT_SHADER@ = 1";
        shader = "$shader";
        unredir = false;
      }
    );
    EOF
    ${pkgs.coreutils}/bin/mv "$temporary" "$runtime_config"

    # Xfwm remains the window manager; only hand its compositing role to picom.
    ${pkgs.xfconf}/bin/xfconf-query \
      -c xfwm4 -p /general/use_compositing -s false || true
    sleep 0.5
    exec ${lib.getExe pkgs.picom} --config "$runtime_config"
  '';
in {
  options.programs.crt-wrapper = {
    enable = lib.mkEnableOption "per-window CRT shader wrapper for XFCE/X11";

    pixelPitch = lib.mkOption {
      type = lib.types.numbers.positive;
      default = 4.0;
      description = ''
        Size in screen pixels of one synthetic CRT source pixel. Arbitrary
        windows do not expose Ghostty's exact font-cell geometry, so the picom
        shader uses this fixed pitch for scanline and reconstruction alignment.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      crtWrap
      crtWindowTuner
      startPicom
      pkgs.picom
    ];

    environment.etc."xdg/autostart/crt-picom.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=CRT window compositor
      Comment=Picom compositor with opt-in per-window CRT shading
      Exec=${startPicom}/bin/crt-picom
      Terminal=false
      Hidden=false
      OnlyShowIn=XFCE;
      X-GNOME-Autostart-enabled=true
    '';
  };
}
