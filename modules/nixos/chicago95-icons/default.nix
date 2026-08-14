{
  lib,
  pkgs,
  ...
}: let
  # Pinned to grassmunk/Chicago95 master; the icon themes live in git only,
  # there is no separate icons release artifact.
  version = "3.0-unstable-2026-06-22";

  src = pkgs.fetchFromGitHub {
    owner = "grassmunk";
    repo = "Chicago95";
    rev = "11415b568e84795f7e0d6aa702b41a2cf23e9381";
    hash = "sha256-BD4iWEuTEZ/8RU+JK9Y9QptPxtzpuvJPIRejlFpRwvg=";
  };

  # Tux variant: same Classic95-derived icon theme, but with Tux branding in
  # place of the Microsoft Windows flag logo. The theme identifier used by
  # GTK/xfconf is the directory name, "Chicago95-tux".
  chicago95-tux-icons = pkgs.stdenvNoCC.mkDerivation {
    pname = "chicago95-tux-icon-theme";
    inherit version src;

    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [pkgs.gtk3];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/icons
      cp -r Icons/Chicago95-tux $out/share/icons/Chicago95-tux

      gtk-update-icon-cache -f -t $out/share/icons/Chicago95-tux || true

      runHook postInstall
    '';

    meta = with lib; {
      description = "Chicago95 (Tux variant) Windows 95-style icon theme";
      homepage = "https://github.com/grassmunk/Chicago95";
      license = with licenses; [gpl3Plus mit];
      platforms = platforms.linux;
    };
  };
in {
  environment.systemPackages = [chicago95-tux-icons];
}
