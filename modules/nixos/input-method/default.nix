{pkgs, ...}: {
  # Japanese (and general CJK) text *input*, independent of the system
  # output locale. fcitx5 runs as a per-session daemon; switch between
  # direct Latin typing and Japanese (mozc) with Ctrl+Space.
  #
  # XFCE is an X11 session and honours XDG autostart, so fcitx5 starts
  # automatically and `i18n.inputMethod` exports GTK_IM_MODULE /
  # QT_IM_MODULE / XMODIFIERS for us. Do NOT also add fcitx5 to
  # environment.systemPackages or addon detection breaks.
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = false; # XFCE/X11
      addons = with pkgs; [
        fcitx5-mozc # Japanese engine
        fcitx5-gtk # client-side input support for GTK apps
      ];
      # Treat the generated config as the source of truth so the setup is
      # reproducible. Drop this (or set false) if you want to tweak fcitx5
      # interactively via fcitx5-configtool and have it persist.
      ignoreUserConfig = true;
      settings.inputMethod = {
        GroupOrder."0" = "Default";
        "Groups/0" = {
          Name = "Default";
          # Matches services.xserver.xkb.layout = "jp".
          "Default Layout" = "jp";
          # Start in direct Latin typing; Ctrl+Space toggles to mozc.
          DefaultIM = "keyboard-jp";
        };
        "Groups/0/Items/0".Name = "keyboard-jp";
        "Groups/0/Items/1".Name = "mozc";
      };
    };
  };
}
