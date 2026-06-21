{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.snapraid-btrfs;

  dataDisks = lib.filter (d: d.role == "data") cfg.disks;
  parityDisks = lib.filter (d: d.role == "parity") cfg.disks;

  dataMountPoints = map (d: d.mountPoint) dataDisks;
  parityFiles = map (d: "${d.mountPoint}/snapraid.parity") parityDisks;
  contentFiles =
    ["/var/snapraid.content"]
    ++ map (d: "${cfg.contentRoot}/${d.name}/snapraid.content") dataDisks;

  snapraidDataDisks = lib.listToAttrs (map (d: {
    name = d.name;
    value = d.mountPoint;
  }) dataDisks);

  snapperConfigs = lib.listToAttrs (map (d: {
    name = d.name;
    value = {
      SUBVOLUME = d.mountPoint;
      TIMELINE_CREATE = false;
      ALLOW_GROUPS = ["wheel"];
    };
  }) dataDisks);

  mkDataFs = d: {
    device = d.device;
    fsType = "btrfs";
    options = ["subvol=data" "nofail"];
  };

  mkContentFs = d: {
    device = d.device;
    fsType = "btrfs";
    options = ["subvol=content" "nofail"];
  };

  mkSnapshotFs = d: {
    device = d.device;
    fsType = "btrfs";
    options = ["subvol=.snapshots" "nofail"];
  };

  mkParityFs = d: {
    device = d.device;
    fsType = "ext4";
    options = ["nofail"];
  };

  # Every entry must be an existing directory: a non-existent path in
  # ReadWritePaths makes systemd's mount-namespace setup fail to apply the
  # writable exceptions under ProtectSystem=strict, which silently leaves the
  # whole array read-only inside the unit. Use the parity *mount points* (the
  # snapraid.parity files don't exist before the first sync) and include each
  # data disk's .snapshots subvolume, where snapraid-btrfs/snapper write.
  readWritePaths = lib.unique (
    dataMountPoints
    ++ dataSnapshotMounts
    ++ parityMountList
    ++ map lib.dirOf contentFiles
  );

  shArr = items: lib.concatMapStringsSep " " lib.escapeShellArg items;

  dataDeviceList = map (d: d.device) dataDisks;
  dataNameList = map (d: d.name) dataDisks;
  contentMountList = map (d: "${cfg.contentRoot}/${d.name}") dataDisks;
  parityDeviceList = map (d: d.device) parityDisks;
  parityNameList = map (d: d.name) parityDisks;
  parityMountList = map (d: d.mountPoint) parityDisks;

  # Idempotent disk initialiser derived from cfg.disks (the single source of
  # truth). Only blank drives are formatted; drives that already contain a
  # filesystem are left untouched, so this is safe to re-run when adding disks.
  initDisksScript = pkgs.writeShellApplication {
    name = "snapraid-btrfs-init-disks";
    runtimeInputs = with pkgs; [util-linux btrfs-progs e2fsprogs coreutils];
    text = ''
      set -euo pipefail

      if [[ "$(id -u)" -ne 0 ]]; then
        echo "Run as root (e.g. sudo snapraid-btrfs-init-disks)." >&2
        exit 1
      fi

      DATA_DEVICES=( ${shArr dataDeviceList} )
      DATA_NAMES=( ${shArr dataNameList} )
      DATA_MOUNTS=( ${shArr dataMountPoints} )
      CONTENT_MOUNTS=( ${shArr contentMountList} )
      PARITY_DEVICES=( ${shArr parityDeviceList} )
      PARITY_NAMES=( ${shArr parityNameList} )
      PARITY_MOUNTS=( ${shArr parityMountList} )

      fs_type() { blkid -o value -s TYPE "$1" 2>/dev/null || true; }
      node_of() { readlink -f "$1" 2>/dev/null || echo "$1"; }
      size_of() { lsblk -dn -o SIZE "$(node_of "$1")" 2>/dev/null | tr -d ' ' || true; }

      to_format_data=()
      for i in "''${!DATA_DEVICES[@]}"; do
        if [[ -z "$(fs_type "''${DATA_DEVICES[$i]}")" ]]; then
          to_format_data+=( "$i" )
        fi
      done

      to_format_parity=()
      for i in "''${!PARITY_DEVICES[@]}"; do
        if [[ -z "$(fs_type "''${PARITY_DEVICES[$i]}")" ]]; then
          to_format_parity+=( "$i" )
        fi
      done

      if [[ ''${#to_format_data[@]} -gt 0 || ''${#to_format_parity[@]} -gt 0 ]]; then
        echo "The following BLANK drives will be PERMANENTLY FORMATTED:"
        echo "(drives that already contain a filesystem are left untouched)"
        for i in "''${to_format_parity[@]}"; do
          printf '  %-8s ext4   %s -> %s (%s)\n' \
            "''${PARITY_NAMES[$i]}" "''${PARITY_DEVICES[$i]}" \
            "$(node_of "''${PARITY_DEVICES[$i]}")" "$(size_of "''${PARITY_DEVICES[$i]}")"
        done
        for i in "''${to_format_data[@]}"; do
          printf '  %-8s btrfs  %s -> %s (%s)\n' \
            "''${DATA_NAMES[$i]}" "''${DATA_DEVICES[$i]}" \
            "$(node_of "''${DATA_DEVICES[$i]}")" "$(size_of "''${DATA_DEVICES[$i]}")"
        done
        echo
        read -r -p "Type YES to format these drives: " confirm
        if [[ "$confirm" != "YES" ]]; then
          echo "Aborted."
          exit 1
        fi
      else
        echo "No blank drives detected; ensuring subvolumes and mountpoints only."
      fi

      for i in "''${to_format_parity[@]}"; do
        echo "==> mkfs.ext4 on ''${PARITY_NAMES[$i]} (''${PARITY_DEVICES[$i]})"
        mkfs.ext4 -F -L "''${PARITY_NAMES[$i]}" "''${PARITY_DEVICES[$i]}"
      done

      for i in "''${to_format_data[@]}"; do
        echo "==> mkfs.btrfs on ''${DATA_NAMES[$i]} (''${DATA_DEVICES[$i]})"
        mkfs.btrfs -f -L "''${DATA_NAMES[$i]}" "''${DATA_DEVICES[$i]}"
      done

      ensure_subvols() {
        local dev="$1"
        local root
        root="$(mktemp -d /run/snapraid-init-XXXXXX)"
        mount "$dev" "$root"
        for sv in data content .snapshots; do
          if [[ ! -e "$root/$sv" ]]; then
            btrfs subvolume create "$root/$sv"
          fi
        done
        # the .snapshots subvol mounts at <data>/.snapshots, so its mountpoint
        # directory must exist inside the data subvolume itself
        mkdir -p "$root/data/.snapshots"
        umount "$root"
        rmdir "$root"
      }

      for i in "''${!DATA_DEVICES[@]}"; do
        dev="''${DATA_DEVICES[$i]}"
        name="''${DATA_NAMES[$i]}"
        t="$(fs_type "$dev")"
        if [[ "$t" != "btrfs" ]]; then
          echo "WARNING: $name ($dev) is type '$t', not btrfs; skipping subvolume setup." >&2
          continue
        fi
        echo "==> ensuring subvolumes on $name"
        ensure_subvols "$dev"
      done

      mkdir -p "''${DATA_MOUNTS[@]}" "''${CONTENT_MOUNTS[@]}" "''${PARITY_MOUNTS[@]}" ${lib.escapeShellArg cfg.poolMount}

      echo
      echo "Disk initialisation complete."
      echo "Next:"
      echo "  sudo systemctl daemon-reload && sudo mount -a"
      echo "  sudo snapraid-btrfs sync"
    '';
  };

  # Each data disk's .snapshots subvolume mount, where snapraid-btrfs/snapper
  # write snapshots (referenced by readWritePaths).
  dataSnapshotMounts = map (mp: "${mp}/.snapshots") dataMountPoints;

  notif = cfg.notifications;
  emailEnabled = notif.email.enable;
  hasSecrets = notif.secretsFile != null;

  # The SMTP password can come from a per-secret file (e.g. deployed by opnix
  # from 1Password) or, failing that, from the legacy KEY=VALUE EnvironmentFile.
  # The file source is preferred; the EnvironmentFile is only wired up as a
  # fallback when passwordFile is not configured.
  smtpPasswordFile = notif.email.passwordFile;
  emailUsesEnvFile = emailEnabled && smtpPasswordFile == null && hasSecrets;

  # Static runner config: it holds no secrets, so it can live in the store.
  # The runner's own (plain-text) email is disabled (sendon empty); status
  # reports are produced by the HTML notifier below instead.
  runnerConf = pkgs.writeText "snapraid-btrfs-runner.conf" ''
    [snapraid-btrfs]
    executable = ${pkgs.snapraid-btrfs}/bin/snapraid-btrfs
    snapper-configs =
    snapper-configs-file =
    pool = false
    pool-dir =
    cleanup = true

    [snapper]
    executable = ${pkgs.snapper}/bin/snapper

    [snapraid]
    executable = ${pkgs.snapraid}/bin/snapraid
    config = /etc/snapraid.conf
    deletethreshold = 40
    touch = false

    [logging]
    file =
    maxsize = 5000

    [email]
    sendon =

    [scrub]
    enabled = true
    plan = 8
    older-than = 10
  '';

  # Renders a formatted HTML status report from the run's journal and emails it.
  # Invoked as a systemd OnSuccess=/OnFailure= handler on the sync unit.
  emailReport = pkgs.writeShellApplication {
    name = "snapraid-btrfs-email-report";
    runtimeInputs = with pkgs; [python3 systemd];
    text = ''
      exec ${pkgs.python3}/bin/python3 \
        ${../../../packages/snapraid-btrfs-email-report.py} "$@"
    '';
  };

  # Non-secret SMTP/identity settings passed to the notifier via the
  # environment; the password is read at runtime from its file (or the legacy
  # EnvironmentFile fallback).
  reportEnv =
    [
      "SR_HOST=${config.networking.hostName}"
      "SR_UNIT=snapraid-btrfs-sync.service"
      "SR_SMTP_HOST=${notif.email.host}"
      "SR_SMTP_PORT=${toString notif.email.port}"
      "SR_SMTP_TLS=${lib.boolToString notif.email.tls}"
      "SR_SMTP_SSL=${lib.boolToString notif.email.ssl}"
      "SR_SMTP_USER=${notif.email.user}"
      "SR_EMAIL_FROM=${notif.email.from}"
      "SR_EMAIL_TO=${notif.email.to}"
      "SR_EMAIL_SUBJECT=${notif.email.subject}"
      # The notifier's smtplib STARTTLS needs the system CA bundle.
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    ]
    ++ lib.optional (smtpPasswordFile != null) "SR_PASSWORD_FILE=${smtpPasswordFile}";

  mkNotify = kind: lib.mkIf emailEnabled {
    description = "Email a snapraid-btrfs ${kind} report";
    serviceConfig =
      {
        Type = "oneshot";
        ExecStart = "${emailReport}/bin/snapraid-btrfs-email-report ${kind}";
        Environment = reportEnv;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service";
      }
      // lib.optionalAttrs emailUsesEnvFile {
        EnvironmentFile = ["-${notif.secretsFile}"];
      };
  };
in {
  options.services.snapraid-btrfs = with lib.types; {
    enable = lib.mkEnableOption "SnapRAID with BTRFS snapshots via snapraid-btrfs";

    guardBareFix = lib.mkOption {
      type = bool;
      default = true;
      description = ''
        Wrap snapraid-btrfs to refuse an unscoped `fix` (no -d/--filter-disk,
        -e or -f). A bare `fix` reverts every data disk to the last sync from
        the live filesystem, overwriting newer changes. Scoped fixes pass
        through. Override at runtime with SNAPRAID_BTRFS_ALLOW_BARE_FIX=1.
      '';
    };

    notifications = {
      secretsFile = lib.mkOption {
        type = nullOr path;
        default = "/etc/snapraid-btrfs/secrets.env";
        description = ''
          Legacy fallback: root-only EnvironmentFile with the SMTP password as
          a `SMTP_PASSWORD=...` line. Only consulted when `email.passwordFile`
          is not set. Kept out of the world-readable Nix store and referenced
          optionally, so a missing file degrades gracefully (the run still
          completes; only the email send fails). Set to null to disable.
        '';
      };

      email = {
        enable = lib.mkEnableOption "email status reports via the runner's built-in SMTP client";
        to = lib.mkOption {
          type = str;
          default = "";
          description = "Destination email address.";
        };
        from = lib.mkOption {
          type = str;
          default = "";
          description = "Sender email address.";
        };
        sendOn = lib.mkOption {
          type = listOf (enum ["success" "error"]);
          default = ["success" "error"];
          description = "Which run outcomes trigger an email.";
        };
        host = lib.mkOption {
          type = str;
          default = "";
          description = "SMTP server hostname.";
        };
        port = lib.mkOption {
          type = port;
          default = 587;
          description = "SMTP server port.";
        };
        user = lib.mkOption {
          type = str;
          default = "";
          description = "SMTP username (password comes from passwordFile, or secretsFile as SMTP_PASSWORD).";
        };
        passwordFile = lib.mkOption {
          type = nullOr path;
          default = null;
          description = ''
            Path to a file containing ONLY the SMTP password (no KEY=VALUE).
            Intended for runtime-deployed secrets such as those provided by
            opnix from 1Password. When set, it takes precedence over
            `SMTP_PASSWORD` from `secretsFile`. A missing/unreadable file
            degrades gracefully (sync still runs; only the email send fails).
          '';
        };
        ssl = lib.mkOption {
          type = bool;
          default = false;
          description = "Use implicit TLS (SMTPS, usually port 465).";
        };
        tls = lib.mkOption {
          type = bool;
          default = true;
          description = "Use STARTTLS (usually port 587).";
        };
        subject = lib.mkOption {
          type = str;
          default = "[SnapRAID] Status Report:";
          description = "Email subject prefix (SUCCESS/ERROR is appended).";
        };
      };
    };

    disks = lib.mkOption {
      type = listOf (submodule {
        options = {
          name = lib.mkOption {
            type = str;
            description = "SnapRAID disk identifier (e.g. disk1, parity1).";
          };
          role = lib.mkOption {
            type = enum ["data" "parity"];
            description = "Whether this disk holds array data or parity.";
          };
          device = lib.mkOption {
            type = str;
            description = "Stable block device path (prefer /dev/disk/by-id/).";
          };
          mountPoint = lib.mkOption {
            type = str;
            description = "Where this disk (or subvolume) is mounted.";
          };
        };
      });
      description = "Physical disks in the SnapRAID array.";
    };

    poolMount = lib.mkOption {
      type = str;
      default = "/mnt/storage";
      description = "MergerFS pool mount point.";
    };

    contentRoot = lib.mkOption {
      type = str;
      default = "/mnt/snapraid-content";
      description = "Parent directory for per-disk SnapRAID content files.";
    };

    mergerfsOptions = lib.mkOption {
      type = listOf str;
      default = [
        "defaults"
        "nofail"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "category.create=mfs"
        "moveonenospc=true"
        "dropcacheonclose=true"
        "minfreespace=100G"
        "fsname=mergerfs"
      ];
    };

    syncAt = lib.mkOption {
      type = str;
      default = "03:00";
      description = "Daily time to run snapraid-btrfs sync.";
    };

    excludes = lib.mkOption {
      type = listOf str;
      default = [
        "*.unrecoverable"
        "/tmp/"
        "/lost+found/"
        "downloads/"
        "appdata/"
        "*.!sync"
        "/.snapshots/"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !emailEnabled || (notif.email.host != "" && notif.email.to != "" && notif.email.from != "");
        message = "services.snapraid-btrfs.notifications.email requires host, to, and from to be set.";
      }
    ];

    nixpkgs.overlays = [
      (final: prev: let
        snapraid-btrfs-unwrapped = final.callPackage ../../../packages/snapraid-btrfs.nix {};
      in {
        inherit snapraid-btrfs-unwrapped;
        snapraid-btrfs =
          if cfg.guardBareFix
          then final.callPackage ../../../packages/snapraid-btrfs-guard.nix {inherit snapraid-btrfs-unwrapped;}
          else snapraid-btrfs-unwrapped;
        snapraid-btrfs-runner = final.callPackage ../../../packages/snapraid-btrfs-runner.nix {};
      })
    ];

    boot.supportedFilesystems = ["btrfs" "fuse.mergerfs"];

    fileSystems =
      lib.listToAttrs (map (d: {
        name = d.mountPoint;
        value = mkDataFs d;
      }) dataDisks)
      // lib.listToAttrs (map (d: {
        name = "${cfg.contentRoot}/${d.name}";
        value = mkContentFs d;
      }) dataDisks)
      // lib.listToAttrs (map (d: {
        name = "${d.mountPoint}/.snapshots";
        value = mkSnapshotFs d;
      }) dataDisks)
      // lib.listToAttrs (map (d: {
        name = d.mountPoint;
        value = mkParityFs d;
      }) parityDisks)
      // {
        "${cfg.poolMount}" = {
          device = lib.concatStringsSep ":" dataMountPoints;
          fsType = "fuse.mergerfs";
          options = cfg.mergerfsOptions;
          depends = dataMountPoints;
        };
      };

    services.snapraid = {
      enable = true;
      exclude = cfg.excludes;
      parityFiles = parityFiles;
      contentFiles = contentFiles;
      dataDisks = snapraidDataDisks;
      touchBeforeSync = false;
      sync.interval = "";
      scrub.interval = "";
    };

    services.snapper.configs = snapperConfigs;

    # We schedule via snapraid-btrfs-sync; suppress the stock module's timers
    # (otherwise they're generated with an empty OnCalendar and land in
    # "bad-setting" state).
    systemd.timers.snapraid-sync.enable = false;
    systemd.timers.snapraid-scrub.enable = false;

    systemd.services.snapraid-btrfs-sync = {
      description = "Synchronize SnapRAID array using BTRFS snapshots";
      startAt = cfg.syncAt;
      # Send a formatted HTML report afterwards (the notifier reads this run's
      # journal). Wired per outcome so it honours notifications.email.sendOn.
      unitConfig = lib.mkIf emailEnabled (
        lib.optionalAttrs (builtins.elem "success" notif.email.sendOn) {
          OnSuccess = "snapraid-btrfs-notify-success.service";
        }
        // lib.optionalAttrs (builtins.elem "error" notif.email.sendOn) {
          OnFailure = "snapraid-btrfs-notify-failure.service";
        }
      );
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = "${pkgs.snapraid-btrfs-runner}/bin/snapraid-btrfs-runner -c ${runnerConf}";
        Nice = 19;
        IOSchedulingPriority = 7;
        CPUSchedulingPolicy = "batch";

        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        # The sync itself does no network I/O (email is handled by the
        # separate notifier unit), so UNIX sockets are all it needs.
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service";
        SystemCallErrorNumber = "EPERM";
        # snapraid-btrfs/snapper create and delete btrfs snapshots, which
        # require CAP_SYS_ADMIN; computing parity over data owned by any user
        # requires CAP_DAC_READ_SEARCH. An empty set makes the sync fail.
        # This is the minimal set this workload needs.
        CapabilityBoundingSet = ["CAP_SYS_ADMIN" "CAP_DAC_READ_SEARCH"];
        AmbientCapabilities = ["CAP_SYS_ADMIN" "CAP_DAC_READ_SEARCH"];
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadOnlyPaths = ["/etc/snapraid.conf" "/etc/snapper"];
        ReadWritePaths = readWritePaths;
      };
    };

    systemd.services.snapraid-btrfs-notify-success = mkNotify "success";
    systemd.services.snapraid-btrfs-notify-failure = mkNotify "failure";

    environment.systemPackages = with pkgs; [
      mergerfs
      snapraid-btrfs
      snapraid-btrfs-runner
      btrfs-progs
      initDisksScript
    ];
  };
}
