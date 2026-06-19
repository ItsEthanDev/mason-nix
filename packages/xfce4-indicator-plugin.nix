{
  lib,
  stdenv,
  fetchurl,
  meson,
  ninja,
  pkg-config,
  gettext,
  glib,
  gtk3,
  libxfce4ui,
  libxfce4util,
  xfce4-panel,
  xfconf,
  libayatana-indicator,
  ayatana-ido,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xfce4-indicator-plugin";
  version = "2.5.0";

  src = fetchurl {
    url = "mirror://xfce/src/panel-plugins/xfce4-indicator-plugin/${lib.versions.majorMinor finalAttrs.version}/xfce4-indicator-plugin-${finalAttrs.version}.tar.xz";
    hash = "sha256-4aKaLEg39T3UglxR8L2B2kLPNubuyF0mbQTD1JURtFE=";
  };

  nativeBuildInputs = [
    gettext
    glib
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    glib
    gtk3
    libxfce4ui
    libxfce4util
    xfce4-panel
    xfconf
    libayatana-indicator
    ayatana-ido
  ];

  meta = {
    description = "Ayatana indicator host for the Xfce panel";
    homepage = "https://docs.xfce.org/panel-plugins/xfce4-indicator-plugin/start";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
})
