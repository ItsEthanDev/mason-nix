{pkgs, ...}: let
  redmond97-se = pkgs.callPackage ../../../pkgs/redmond97-se/package.nix {};
in {
  # Installing the package puts the themes under share/themes and the Obsidian
  # icon set under share/icons in the system profile, which Xfce4 (GTK2/3/4 and
  # xfwm4) picks up automatically via XDG_DATA_DIRS. Select a theme afterwards
  # with xfce4-appearance-settings.
  environment.systemPackages = [redmond97-se];
}
