{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.mpc-qt;
  preferWayland = lib.boolToString cfg.tweaksPreferWayland;

  patchSettingsScript = ''
    settings="$HOME/.config/mpc-qt/settings.json"
    if [ -f "$settings" ]; then
      tmp="$(mktemp)"
      if ${pkgs.jq}/bin/jq '.tweaksPreferWayland = ${preferWayland}' "$settings" > "$tmp"; then
        mv "$tmp" "$settings"
      else
        rm -f "$tmp"
      fi
    fi
  '';

  mpc-qt = pkgs.symlinkJoin {
    name = "mpc-qt";
    paths = [pkgs.mpc-qt];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      mv $out/bin/mpc-qt $out/bin/.mpc-qt-unwrapped
      makeWrapper $out/bin/.mpc-qt-unwrapped $out/bin/mpc-qt \
        --prefix PATH : ${lib.makeBinPath [pkgs.jq]} \
        --run '${patchSettingsScript}'
    '';
  };
in {
  options.programs.mpc-qt = {
    enable = lib.mkEnableOption "mpc-qt media player";
    tweaksPreferWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Prefer native Wayland rendering in mpc-qt.
        Required on NVIDIA + Wayland to avoid a blank window.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [mpc-qt];

    system.activationScripts.mpc-qt-settings = lib.stringAfter ["users"] (
      lib.concatStrings (
        lib.mapAttrsToList (
          name: user:
            lib.optionalString user.isNormalUser ''
              settings="${user.home}/.config/mpc-qt/settings.json"
              if [ -f "$settings" ]; then
                tmp="$(mktemp)"
                if ${pkgs.jq}/bin/jq '.tweaksPreferWayland = ${preferWayland}' "$settings" > "$tmp"; then
                  chown --reference="$settings" "$tmp"
                  mv "$tmp" "$settings"
                else
                  rm -f "$tmp"
                fi
              fi
            ''
        ) config.users.users
      )
    );
  };
}
