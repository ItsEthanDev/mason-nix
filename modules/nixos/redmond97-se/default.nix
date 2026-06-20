{
  lib,
  pkgs,
  ...
}: let
  version = "2.13";

  src = pkgs.fetchurl {
    url = "https://codeberg.org/Sliver_X/Redmond97-SE/releases/download/v${version}/Redmond97-SE_v${version}.tar.xz";
    hash = "sha256-L4FMQqu2VAlr6egjjsUZy7N0nPFpsPeOfL7HR0riips=";
  };

  # Wallpapers live in git only; the release tarball does not include them.
  wallpaperSrc = pkgs.fetchgit {
    url = "https://codeberg.org/Sliver_X/Redmond97-SE";
    rev = "refs/tags/v${version}";
    sparseCheckout = ["wallpapers"];
    hash = "sha256-zyRlAUZdRoCRz7cCtUHZoEv6zmKZCsKnwO/u0RsQJyQ=";
  };

  redmond97-se = pkgs.stdenvNoCC.mkDerivation {
    pname = "redmond97-se";
    inherit version;
    src = src;

    dontUnpack = true;
    nativeBuildInputs = [pkgs.xz pkgs.gnused];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/themes
      tar -xJf $src themes/themes-v${version}.tar.xz -O \
        | tar -xJ -C $out/share/themes --strip-components=1

      mkdir -p $out/share/icons
      tar -xJf $src icons/Obsidian_Pure_v2.08.tar.xz -O \
        | tar -xJ -C $out/share/icons

      mkdir -p $out/share/redmond97-se
      tar -xJf $src -C $out/share/redmond97-se builder extras

      mkdir -p $out/share/xfce4-panel-profiles/layouts
      cp $out/share/redmond97-se/extras/xfce4-panel-profiles/*.tar.bz2 \
        $out/share/xfce4-panel-profiles/layouts/

      mkdir -p $out/share/backgrounds/redmond97-se
      cp -r ${wallpaperSrc}/wallpapers/* $out/share/backgrounds/redmond97-se/
      
      mkdir -p $out/bin
      ln -s $out/share/redmond97-se/extras/gtk2-scale $out/bin/gtk2-scale
      ln -s $out/share/redmond97-se/extras/r97se-fixes.sh $out/bin/r97se-fixes
      ln -s $out/share/redmond97-se/builder/gen_theme.sh $out/bin/redmond97-gen-theme
      ln -s $out/share/redmond97-se/builder/make-install-all-presets.sh $out/bin/redmond97-install-all-presets

      find $out/share/icons -type l ! -exec test -e {} \; -delete

      # GTK rejects scale(50%); Zen and newer GTK log parse errors without this.
      find $out/share/themes -name gtk-xfce4.css -exec sed -i 's/scale(50%)/scale(0.5)/g' {} +
      # Deprecated on GTK 3.20+; removing silences harmless but noisy warnings.
      find $out/share/themes -name gtk-general.css -exec sed -i '/scrollbars-within-bevel/d' {} +

      runHook postInstall
    '';

    meta = with lib; {
      description = "Windows 95C UI themes for GTK2/3/4, Xfce, and Wine";
      homepage = "https://codeberg.org/Sliver_X/Redmond97-SE";
    };
  };
in {
  environment.systemPackages = [redmond97-se];
}
