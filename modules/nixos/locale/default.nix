{
  pkgs,
  lib,
  ...
}: let
  timezone = "America/Phoenix";
  english = "en_US.UTF-8";
  japanese = "ja_JP.UTF-8";

  # Per-category formatting (dates, currency, paper size, etc.). LC_MESSAGES
  # is intentionally omitted so it follows LANG, which is what flips the
  # actual UI translation language.
  localeSettings = identifier: {
    LC_ADDRESS = identifier;
    LC_IDENTIFICATION = identifier;
    LC_MEASUREMENT = identifier;
    LC_MONETARY = identifier;
    LC_NAME = identifier;
    LC_NUMERIC = identifier;
    LC_PAPER = identifier;
    LC_TELEPHONE = identifier;
    LC_TIME = identifier;
  };

  # Convenience wrapper to flip the system locale between the English base
  # config and the `japanese` specialisation without rebooting. The system
  # profile always points at the English base, with the specialisation as a
  # child, so both targets are reachable regardless of which one is booted.
  langSwitch = pkgs.writeShellScriptBin "lang-switch" ''
    set -eu

    profile=/nix/var/nix/profiles/system

    usage() {
      echo "lang-switch — activate the English or Japanese system locale" >&2
      echo "" >&2
      echo "usage: lang-switch en|ja|status" >&2
      echo "  en      activate the English (base) configuration" >&2
      echo "  ja      activate the Japanese specialisation" >&2
      echo "  status  show the locale recorded in /etc/locale.conf" >&2
    }

    case "''${1:-}" in
      en | english)
        cfg="$profile"
        name="English"
        ;;
      ja | japanese)
        cfg="$profile/specialisation/japanese"
        name="Japanese"
        ;;
      status)
        ${pkgs.gnugrep}/bin/grep -E '^(LANG|LANGUAGE)=' /etc/locale.conf 2>/dev/null \
          || echo "no LANG set in /etc/locale.conf"
        exit 0
        ;;
      *)
        usage
        exit 2
        ;;
    esac

    stc="$cfg/bin/switch-to-configuration"
    if [ ! -x "$stc" ]; then
      echo "lang-switch: $stc not found — run 'sudo nixos-rebuild switch' first." >&2
      exit 1
    fi

    echo "Activating $name configuration…"
    sudo "$stc" switch

    echo ""
    echo "Done. Log out and back in so your graphical session (and conky) pick up the new language."
  '';
in {
  time.timeZone = timezone;

  environment.systemPackages = [langSwitch];

  # Both locales are always built; only the active LANG differs between the
  # base config and the `japanese` specialisation below.
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "ja_JP.UTF-8/UTF-8"
  ];
  fonts.packages = [pkgs.noto-fonts-cjk-sans];

  # Default boot entry: English output.
  i18n.defaultLocale = english;
  i18n.extraLocaleSettings = localeSettings english;

  # `nixos-rebuild` produces an extra GRUB entry "... (japanese)". Boot it
  # for a fully Japanese UI, or switch at runtime with `lang-switch ja` /
  # `lang-switch en` (defined above), then log out and back in so the
  # graphical session picks up the new LANG.
  specialisation.japanese.configuration = {
    i18n.defaultLocale = lib.mkForce japanese;
    i18n.extraLocaleSettings =
      lib.mkForce (localeSettings japanese
        // {
          # gettext translation fallback chain: Japanese first, then English.
          LANGUAGE = "ja_JP:ja:en_US:en";
        });
  };
}
