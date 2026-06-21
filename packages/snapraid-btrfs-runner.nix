# Packages only the runner script + its runtime deps. The runner config is
# owned by the NixOS module (rendered at runtime with the SMTP password), which
# always invokes this with `-c <config>`, so no config is baked in here.
{
  symlinkJoin,
  fetchFromGitHub,
  writeScriptBin,
  makeWrapper,
  python3,
  snapraid,
  snapraid-btrfs,
  snapper,
}: let
  name = "snapraid-btrfs-runner";
  src = fetchFromGitHub {
    owner = "fmoledina";
    repo = "snapraid-btrfs-runner";
    rev = "afb83c67c61fdf3769aab95dba6385184066e119";
    sha256 = "sha256-M8LXxsc7jEn5GsiXAKykmFUgsij2aOIenw1Dx+/5Rww=";
  };
  deps = [python3 snapraid snapraid-btrfs snapper];
  script =
    (writeScriptBin name (builtins.readFile (src + "/snapraid-btrfs-runner.py")))
    .overrideAttrs (old: {
      buildCommand = "${old.buildCommand}\n patchShebangs $out";
    });
in
  symlinkJoin {
    inherit name;
    paths = [script] ++ deps;
    buildInputs = [makeWrapper python3];
    postBuild = ''
      wrapProgram $out/bin/${name} --set PATH $out/bin
    '';
  }
