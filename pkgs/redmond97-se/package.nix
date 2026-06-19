{
  lib,
  stdenvNoCC,
  fetchFromGitea,
  makeWrapper,
  glib,
  xfconf,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "redmond97-se";
  version = "2.13";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "Sliver_X";
    repo = "Redmond97-SE";
    rev = "23cc4b570744300398ec45be83db2fff394c2c80"; # v2.13
    hash = "sha256-Su8EpVALEzUsxPw37drbUs3fIbbFAsMhjDabB/tTENo=";
  };

  nativeBuildInputs = [makeWrapper];

  # The upstream Obsidian-Pure icon archive ships a handful of relative
  # symlinks whose targets aren't present, which is harmless for an icon theme
  # but otherwise fails the noBrokenSymlinks fixup hook.
  dontCheckForBrokenSymlinks = true;

  installPhase = ''
    runHook preInstall

    # Keep the complete upstream source tree (builder, presets, XPM_Scaler,
    # screenshots, docs, raw archives, etc.) so nothing is excluded.
    mkdir -p "$out/share/redmond97-se"
    cp -r . "$out/share/redmond97-se"
    chmod -R u+w "$out/share/redmond97-se"

    mkdir -p \
      "$out/share/themes" \
      "$out/share/icons" \
      "$out/share/backgrounds/redmond97-se" \
      "$out/share/xfce4-panel-profiles/layouts"

    # Pre-built GTK2/3/4 + Xfwm4 + Wine themes. The archive wraps everything in
    # a top-level "themes/" dir, so strip it to land themes in share/themes.
    tar -xf themes/themes-v2.13.tar.xz -C "$out/share/themes" --strip-components=1

    # The bundled Obsidian-Pure icon set (12 colour variants), already laid out
    # as icon-theme directories at the archive root.
    tar -xf icons/Obsidian_Pure_v2.08.tar.xz -C "$out/share/icons"

    # Companion wallpapers; exposed where xfdesktop's backdrop chooser scans.
    install -Dm644 wallpapers/*.png -t "$out/share/backgrounds/redmond97-se"

    # xfce4-panel-profiles layouts (Win9x / WinNT6 / Deskbar / etc.) so they
    # show up in that tool's Backup/Restore menu.
    install -Dm644 extras/xfce4-panel-profiles/*.tar.bz2 \
      -t "$out/share/xfce4-panel-profiles/layouts"

    # Helper scripts from extras/, wrapped with their runtime tools so they work
    # outside an interactive Xfce session.
    install -Dm755 extras/r97se-fixes.sh "$out/bin/r97se-fixes.sh"
    install -Dm755 extras/gtk2-scale "$out/bin/gtk2-scale"
    patchShebangs "$out/bin"
    wrapProgram "$out/bin/r97se-fixes.sh" \
      --prefix PATH : ${lib.makeBinPath [glib xfconf]}
    wrapProgram "$out/bin/gtk2-scale" \
      --prefix PATH : ${lib.makeBinPath [glib]}

    runHook postInstall
  '';

  meta = {
    description = "Windows 95C (OSR 2.5) UI recreation for GTK2/3/4, Xfwm4 and Wine, with the Obsidian-Pure icon set, wallpapers and Xfce4 panel profiles";
    homepage = "https://codeberg.org/Sliver_X/Redmond97-SE";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
