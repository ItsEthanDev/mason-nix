{
  symlinkJoin,
  fetchFromGitHub,
  writeScriptBin,
  writeTextFile,
  makeWrapper,
  python3,
  snapraid,
  snapraid-btrfs,
  snapper,
}: let
  name = "snapraid-btrfs-runner";
  runnerConfig = writeTextFile {
    name = "snapraid-btrfs-runner.conf";
    text = ''
      [snapraid-btrfs]
      executable = ${snapraid-btrfs}/bin/snapraid-btrfs
      snapper-configs =
      snapper-configs-file =
      pool = false
      pool-dir =
      cleanup = true

      [snapper]
      executable = ${snapper}/bin/snapper

      [snapraid]
      executable = ${snapraid}/bin/snapraid
      config = /etc/snapraid.conf
      deletethreshold = 40
      touch = false

      [logging]
      file =
      maxsize = 5000

      [email]
      sendon =
      short = false
      subject = [SnapRAID] Status Report:
      from =
      to =
      maxsize = 500

      [smtp]
      host =
      port = 587
      ssl = false
      tls = true
      user =
      password =

      [scrub]
      enabled = true
      plan = 8
      older-than = 10
    '';
    destination = "/etc/${name}.conf";
  };
  src = fetchFromGitHub {
    owner = "fmoledina";
    repo = "snapraid-btrfs-runner";
    rev = "afb83c67c61fdf3769aab95dba6385184066e119";
    sha256 = "sha256-M8LXxsc7jEn5GsiXAKykmFUgsij2aOIenw1Dx+/5Rww=";
  };
  deps = [python3 runnerConfig snapraid snapraid-btrfs snapper];
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
      wrapProgram $out/bin/${name} \
        --add-flags "-c ${runnerConfig}/etc/${name}.conf" \
        --set PATH $out/bin
    '';
  }
