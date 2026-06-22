{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.conky;

  nvidiaDriverPackage =
    config.hardware.nvidia.package or config.boot.kernelPackages.nvidiaPackages.stable;
  nvidiaDriverBin = if nvidiaDriverPackage ? bin then nvidiaDriverPackage.bin else nvidiaDriverPackage;
  nvidiaSmi = "${nvidiaDriverBin}/bin/nvidia-smi";
  pactl = "${pkgs.pulseaudio}/bin/pactl";
  sensors = "${pkgs.lm_sensors}/bin/sensors";

  getSinkVolume = pkgs.writeShellScript "conky-get-sink-volume" ''
    ${pactl} get-sink-volume @DEFAULT_SINK@ \
      | ${pkgs.gnugrep}/bin/grep -oP '\d+(?=%)' \
      | ${pkgs.coreutils}/bin/head -1
  '';

  getSinkVolumeBar = pkgs.writeShellScript "conky-get-sink-volume-bar" ''
    vol=$(${getSinkVolume})
    ${pkgs.gawk}/bin/awk -v v="$vol" 'BEGIN { if (v + 0 > 100) print 100; else print v + 0 }'
  '';

  formatCalendar = pkgs.writeShellScript "conky-format-calendar" (builtins.readFile ./format-calendar.sh);

  substitute = file: replacements:
    lib.foldl'
      (acc: kv: lib.replaceStrings [(lib.elemAt kv 0)] [(lib.elemAt kv 1)] acc)
      (lib.readFile file)
      replacements;

  # Exo 2 and Space Mono have no dedicated nixpkgs font attrs; subset from google-fonts.
  conkyFonts = pkgs.runCommand "conky-exo2-spacemono-fonts" {} ''
    mkdir -p $out/share/fonts/truetype
    cp ${pkgs.google-fonts}/share/fonts/truetype/Exo2*.ttf $out/share/fonts/truetype/
    cp ${pkgs.google-fonts}/share/fonts/truetype/SpaceMono*.ttf $out/share/fonts/truetype/
  '';

  staticSubstitutions = [
    ["@CPU_MODEL@" cfg.cpuModel]
    ["@GPU_MODEL@" cfg.gpuModel]
    ["@FILESYSTEM_LABEL@" cfg.filesystemLabel]
    ["@WIFI_INTERFACE@" cfg.wifiInterface]
    ["@ETHERNET_INTERFACE@" cfg.ethernetInterface]
    ["@NVIDIA_SMI@" nvidiaSmi]
    ["@SENSORS@" sensors]
    ["@PACTL@" pactl]
    ["@GET_SINK_VOLUME@" "${getSinkVolume}"]
    ["@GET_SINK_VOLUME_BAR@" "${getSinkVolumeBar}"]
    ["@FORMAT_CALENDAR@" "${formatCalendar}"]
  ];

  systemTemplate = substitute ./system.conf staticSubstitutions;
  journalTemplate = substitute ./journal.conf staticSubstitutions;
  timeTemplate = substitute ./time.conf staticSubstitutions;

  templateDir = pkgs.runCommand "conky-templates" {} ''
    mkdir -p $out
    cp ${pkgs.writeText "system.conf" systemTemplate} $out/system.conf
    cp ${pkgs.writeText "journal.conf" journalTemplate} $out/journal.conf
    cp ${pkgs.writeText "time.conf" timeTemplate} $out/time.conf
  '';

  genCpuLines = pkgs.writeShellScript "conky-gen-cpu-lines" (builtins.readFile ./gen-cpu-lines.sh);
  readGtkColors = pkgs.writeShellScript "conky-read-gtk-colors" (builtins.readFile ./read-gtk-colors.sh);

  conkyStart = pkgs.writeShellScriptBin "conky-start" ''
    set -eu

    templateDir=${templateDir}
    configDir="''${XDG_RUNTIME_DIR:-/tmp}/conky"
    mkdir -p "$configDir"

    eval "$(${readGtkColors})"

    escape_sed() {
      printf '%s' "$1" | ${pkgs.gnused}/bin/sed 's/[\\&|#]/\\&/g'
    }

    COLOR_DEFAULT_S=$(escape_sed "$COLOR_DEFAULT")
    COLOR1_S=$(escape_sed "$COLOR1")
    COLOR2_S=$(escape_sed "$COLOR2")
    COLOR3_S=$(escape_sed "$COLOR3")

    # Detect logical CPU count and primary display width at session start.
    cores=$(${pkgs.coreutils}/bin/nproc)
    width=$(${pkgs.xrandr}/bin/xrandr --current 2>/dev/null \
      | ${pkgs.gawk}/bin/awk '$2 == "connected" { print $3; exit }' \
      | ${pkgs.coreutils}/bin/cut -dx -f1)
    if ! printf '%s\n' "$width" | ${pkgs.gnugrep}/bin/grep -qE '^[0-9]+$'; then
      width=1920
    fi

    columnGap=${toString cfg.columnGap}
    systemW=590
    timeW=600
    journalW=590
    totalW=$((systemW + columnGap + timeW + columnGap + journalW))
    startX=$(((width - totalW) / 2))
    systemGapX=$startX
    timeGapX=$((startX + systemW + columnGap))
    journalGapX=$((startX + systemW + columnGap + timeW + columnGap))

    cpuLinesFile="$configDir/cpu-lines.txt"
    ${genCpuLines} "$cpuLinesFile" "$cores"

    render() {
      local template=$1
      local output=$2

      ${pkgs.gnused}/bin/sed \
        -e "/@CPU_CORE_LINES@/{
          r $cpuLinesFile
          d
        }" \
        -e "s|@SYSTEM_GAP_X@|$systemGapX|g" \
        -e "s|@JOURNAL_GAP_X@|$journalGapX|g" \
        -e "s|@TIME_GAP_X@|$timeGapX|g" \
        -e "s|@COLOR_DEFAULT@|$COLOR_DEFAULT_S|g" \
        -e "s|@COLOR1@|$COLOR1_S|g" \
        -e "s|@COLOR2@|$COLOR2_S|g" \
        -e "s|@COLOR3@|$COLOR3_S|g" \
        "$template" > "$output"
    }

    render "$templateDir/system.conf" "$configDir/system.conf"
    render "$templateDir/journal.conf" "$configDir/journal.conf"
    render "$templateDir/time.conf" "$configDir/time.conf"

    ${pkgs.procps}/bin/pkill -x conky || true

    ${pkgs.conky}/bin/conky -c "$configDir/system.conf" &
    ${pkgs.conky}/bin/conky -c "$configDir/journal.conf" &
    ${pkgs.conky}/bin/conky -c "$configDir/time.conf" &

    if [ "''${CONKY_FROM_WATCHER:-}" != 1 ] && command -v xfconf-query >/dev/null 2>&1; then
      watch_pid_file="$configDir/theme-watch.pid"
      if [ ! -f "$watch_pid_file" ] || ! kill -0 "$(cat "$watch_pid_file")" 2>/dev/null; then
        (
          last_theme=$THEME_NAME
          while sleep 3; do
            current=$(${pkgs.xfce.xfconf}/bin/xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
            if [ -n "$current" ] && [ "$current" != "$last_theme" ]; then
              last_theme=$current
              CONKY_FROM_WATCHER=1 "$0"
            fi
          done
        ) &
        echo $! > "$watch_pid_file"
      fi
    fi
  '';

  journalAccessScript = pkgs.writeShellScript "conky-journal-access" ''
    for u in $(awk -F: '($3 >= 1000) && ($3 < 65534) { print $1 }' /etc/passwd); do
      ${pkgs.shadow}/bin/usermod -aG systemd-journal "$u" 2>/dev/null || true
    done
  '';
in {
  options.services.conky = {
    enable = lib.mkEnableOption "Conky desktop overlays";

    cpuModel = lib.mkOption {
      type = lib.types.str;
      default = "CPU";
      description = "CPU model label shown in the system panel.";
    };

    gpuModel = lib.mkOption {
      type = lib.types.str;
      default = "NVIDIA";
      description = "GPU model label shown in the system panel.";
    };

    filesystemLabel = lib.mkOption {
      type = lib.types.str;
      default = "Root";
      description = "Label for the root filesystem row.";
    };

    wifiInterface = lib.mkOption {
      type = lib.types.str;
      default = "wlp4s0";
      description = "Wireless network interface name.";
    };

    ethernetInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp5s0";
      description = "Ethernet network interface name.";
    };

    columnGap = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Pixels between the system, clock, and journal columns.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      conky
      conkyStart
      xrandr
      xfce.xfconf
      glib
    ];

    fonts.packages = with pkgs; [
      # Sarasa Mono J covers Latin + CJK in one duospaced family (CJK glyphs
      # are exactly 2x Latin width), so conky panels render Japanese journal
      # output and the localized `cal` grid without tofu or misalignment.
      sarasa-gothic
      conkyFonts # Exo 2 (panel headers)
    ];

    environment.etc."xdg/autostart/conky.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Conky
      Comment=Desktop overlays (system, clock, journal)
      Exec=${conkyStart}/bin/conky-start
      Terminal=false
      Hidden=false
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=XFCE;
    '';

    system.activationScripts.conkyJournalAccess = lib.stringAfter ["users" "groups"] ''
      ${journalAccessScript}
    '';
  };
}
