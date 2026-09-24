{
  config,
  lib,
  ...
}: let
  presetName = "ATH-R70x-FiiO-K7";

  bands = [
    {
      frequency = 20.0;
      gain = 7.9;
      q = 0.6;
    }
    {
      frequency = 20.0;
      gain = 0.9;
      q = 2.0;
    }
    {
      frequency = 200.0;
      gain = -2.8;
      q = 0.9;
    }
    {
      frequency = 3800.0;
      gain = -2.5;
      q = 2.0;
    }
    {
      frequency = 4500.0;
      gain = 2.4;
      q = 2.0;
    }
    {
      frequency = 4700.0;
      gain = 4.1;
      q = 2.0;
    }
    {
      frequency = 8000.0;
      gain = -3.3;
      q = 1.6;
    }
    {
      frequency = 10000.0;
      gain = 10.6;
      q = 1.8;
    }
    {
      frequency = 15000.0;
      gain = -2.8;
      q = 0.6;
    }
  ];

  mkBand = band:
    band
    // {
      mode = "RLC (BT)";
      mute = false;
      slope = "x1";
      solo = false;
      type = "Bell";
      width = 4.0;
    };

  equalizerBands =
    lib.listToAttrs
    (lib.imap0 (index: band: {
        name = "band${toString index}";
        value = mkBand band;
      })
      bands);
in {
  home = {
    username = "masons";
    homeDirectory = "/home/masons";
    stateVersion = "26.05";
  };

  dconf.settings = {
    "org/entangle-photo/manager/img" = {
      # The 5D Mark II preview already has the correct orientation.
      flip-horizontally = false;
      flip-vertically = false;
    };
    "org/entangle-photo/manager/interface".plugins = ["virtual_camera"];
  };

  services.easyeffects = {
    enable = true;
    preset = presetName;
    settings.StreamOutputs.outputDevice =
      "alsa_output.usb-GuangZhou_FiiO_Electronics_Co._Ltd_FiiO_K7-00.analog-stereo";
    extraPresets.${presetName}.output = {
      blocklist = [];
      "plugins_order" = ["equalizer#0"];
      "equalizer#0" = {
        balance = 0.0;
        bypass = false;
        input-gain = -10.6;
        left = equalizerBands;
        mode = "IIR";
        num-bands = builtins.length bands;
        output-gain = 0.0;
        pitch-left = 0.0;
        pitch-right = 0.0;
        right = equalizerBands;
        split-channels = false;
      };
    };
  };
}
