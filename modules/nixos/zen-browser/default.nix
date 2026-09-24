{pkgs, zen-browser, ...}: let
  packages = zen-browser.packages.${pkgs.stdenv.hostPlatform.system};

  # nixpkgs' Firefox wrapper now checks withFFmpeg, while the Zen flake still
  # exposes the former ffmpegSupport passthru attribute.
  zen-browser-unwrapped = packages.zen-browser-unwrapped.overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      withFFmpeg = true;
    };
  });

  # NVIDIA 610.x EGL-on-X11 (libnvidia-egl-xlib) SIGSEGVs in
  # libnvidia-eglcore during eglMakeCurrent on the CanvasRenderer
  # thread. Keep WebRender on the older GLX path and fall canvas back
  # to CPU so the browser does not take the crashing EGL context.
  # https://bbs.archlinux.org/viewtopic.php?id=299879
  # https://bugzilla.mozilla.org/show_bug.cgi?id=1850285
  zen-browser-with-ffmpeg = pkgs.wrapFirefox zen-browser-unwrapped {
    pname = "zen-browser";
    extraPrefs = ''
      pref("gfx.canvas.accelerated", false);
      pref("gfx.x11-egl.force-disabled", true);
    '';
  };
in {
  environment.systemPackages = [
    zen-browser-with-ffmpeg
  ];
}
