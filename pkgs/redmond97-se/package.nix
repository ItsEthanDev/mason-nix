{
  lib,
  stdenvNoCC,
  fetchFromGitea,
  xz,
  includeIcons ? true,
}:

stdenvNoCC.mkDerivation rec {
  pname = "redmond97-se";
  version = "2.13";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "Sliver_X";
    repo = "Redmond97-SE";
    rev = "23cc4b570744300398ec45be83db2fff394c2c80";
    hash = "sha256-Su8EpVALEzUsxPw37drbUs3fIbbFAsMhjDabB/tTENo=";
  };

  nativeBuildInputs = [xz];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/themes
    tar -xJf themes/themes-v${version}.tar.xz -C $out/share/themes --strip-components=1

    ${lib.optionalString includeIcons ''
      mkdir -p $out/share/icons
      tar -xJf icons/Obsidian_Pure_v2.08.tar.xz -C $out/share/icons
      find $out/share/icons -xtype l -delete
    ''}

    runHook postInstall
  '';

  meta = {
    description = "Windows 95C UI theme for GTK/Xfce (Redmond97 SE)";
    homepage = "https://codeberg.org/Sliver_X/Redmond97-SE";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
