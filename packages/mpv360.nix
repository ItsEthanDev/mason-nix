{
  lib,
  stdenv,
  fetchFromGitHub,
}: stdenv.mkDerivation {
  pname = "mpv360";
  version = "0-unstable-2025-06-21";

  src = fetchFromGitHub {
    owner = "kasper93";
    repo = "mpv360";
    rev = "76f112128d4f372eaee07436ae3a879adafdcc88";
    hash = "sha256-Kb9CfKKIhDkY389a2L5G+lmrKCk8gDlZiO7IL3znL4U=";
  };

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/scripts $out/shaders $out/script-opts
    cp scripts/mpv360.lua $out/scripts/
    cp shaders/mpv360.glsl $out/shaders/
    cp script-opts/mpv360.conf $out/script-opts/
  '';

  meta = {
    description = "Interactive 360° video viewer scripts and shaders for mpv";
    homepage = "https://github.com/kasper93/mpv360";
    license = lib.licenses.gpl3Only;
  };
}
