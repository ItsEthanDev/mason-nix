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

  readWritePaths = lib.unique (
    dataMountPoints
    ++ parityFiles
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

  # Pre-flight verifier used as ExecStartPre for the sync service (and runnable
  # by hand). Fails non-zero if any configured disk is missing, unmounted, not
  # the expected filesystem, or unwritable (parity), so systemd aborts the sync
  # before SnapRAID can ever touch parity with a degraded array.
  dataSnapshotMounts = map (mp: "${mp}/.snapshots") dataMountPoints;

  preflightScript = pkgs.writeShellApplication {
    name = "snapraid-btrfs-preflight";
    runtimeInputs = with pkgs; [util-linux btrfs-progs coreutils];
    text = ''
      DATA_NAMES=( ${shArr dataNameList} )
      DATA_DEVICES=( ${shArr dataDeviceList} )
      DATA_MOUNTS=( ${shArr dataMountPoints} )
      DATA_SNAPSHOT_MOUNTS=( ${shArr dataSnapshotMounts} )
      CONTENT_MOUNTS=( ${shArr contentMountList} )
      PARITY_NAMES=( ${shArr parityNameList} )
      PARITY_DEVICES=( ${shArr parityDeviceList} )
      PARITY_MOUNTS=( ${shArr parityMountList} )

      fail=0
      err() {
        echo "snapraid-btrfs-preflight: FAIL: $*" >&2
        fail=1
      }

      check_device() {
        # $1 = label, $2 = stable device path
        [[ -e "$2" ]] || err "$1: device $2 is not present (disk missing?)"
      }

      check_mounted() {
        # $1 = label, $2 = mountpoint; returns non-zero if not mounted
        if mountpoint -q "$2"; then
          return 0
        fi
        err "$1: $2 is not mounted"
        return 1
      }

      for i in "''${!DATA_NAMES[@]}"; do
        name="''${DATA_NAMES[$i]}"
        check_device "$name" "''${DATA_DEVICES[$i]}"
        if check_mounted "$name" "''${DATA_MOUNTS[$i]}"; then
          if ! btrfs subvolume show "''${DATA_MOUNTS[$i]}" >/dev/null 2>&1; then
            err "$name: ''${DATA_MOUNTS[$i]} is not a btrfs subvolume"
          fi
          ls -A "''${DATA_MOUNTS[$i]}" >/dev/null 2>&1 ||
            err "$name: cannot read ''${DATA_MOUNTS[$i]}"
        fi
        check_mounted "$name (.snapshots)" "''${DATA_SNAPSHOT_MOUNTS[$i]}" || true
        check_mounted "$name (content)" "''${CONTENT_MOUNTS[$i]}" || true
      done

      for i in "''${!PARITY_NAMES[@]}"; do
        name="''${PARITY_NAMES[$i]}"
        check_device "$name" "''${PARITY_DEVICES[$i]}"
        if check_mounted "$name" "''${PARITY_MOUNTS[$i]}"; then
          probe="''${PARITY_MOUNTS[$i]}/.snapraid-btrfs-preflight.$$"
          if touch "$probe" 2>/dev/null; then
            rm -f "$probe"
          else
            err "$name: ''${PARITY_MOUNTS[$i]} is not writable"
          fi
        fi
      done

      if [[ "$fail" -ne 0 ]]; then
        echo "snapraid-btrfs-preflight: refusing to continue; array is not healthy." >&2
        exit 1
      fi
      echo "snapraid-btrfs-preflight: OK - all data and parity disks mounted and healthy."
    '';
  };

  notif = cfg.notifications;
  emailEnabled = notif.email.enable;
  ntfyEnabled = notif.ntfy.enable;
  hasSecrets = notif.secretsFile != null;
  runtimeRunnerConf = "/run/snapraid-btrfs/runner.conf";

  # Runner config template rendered at runtime so the SMTP password is pulled
  # from the secrets EnvironmentFile instead of being baked into the store.
  runnerConfTemplate = pkgs.writeText "snapraid-btrfs-runner.conf.in" ''
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
    sendon = ${lib.concatStringsSep "," notif.email.sendOn}
    short = false
    subject = ${notif.email.subject}
    from = ${notif.email.from}
    to = ${notif.email.to}
    maxsize = 500

    [smtp]
    host = ${notif.email.host}
    port = ${toString notif.email.port}
    ssl = ${lib.boolToString notif.email.ssl}
    tls = ${lib.boolToString notif.email.tls}
    user = ${notif.email.user}
    password = ''${SMTP_PASSWORD}

    [scrub]
    enabled = true
    plan = 8
    older-than = 10
  '';

  renderRunnerConf = pkgs.writeShellApplication {
    name = "snapraid-btrfs-render-runner-conf";
    runtimeInputs = with pkgs; [gettext coreutils];
    text = ''
      out="''${RUNTIME_DIRECTORY%%:*}/runner.conf"
      umask 077
      # Restrict substitution to SMTP_PASSWORD; the literal var list is meant
      # to reach envsubst unexpanded, hence the single quotes.
      # shellcheck disable=SC2016
      envsubst '$SMTP_PASSWORD' < ${runnerConfTemplate} > "$out"
    '';
  };

  ntfyScript = pkgs.writeShellApplication {
    name = "snapraid-btrfs-notify";
    runtimeInputs = with pkgs; [curl coreutils systemd];
    text = ''
      status="''${1:-failure}"
      server=${lib.escapeShellArg notif.ntfy.server}
      topic=${lib.escapeShellArg notif.ntfy.topic}
      host=${lib.escapeShellArg config.networking.hostName}

      case "$status" in
        success)
          prio=${lib.escapeShellArg notif.ntfy.successPriority}
          title="SnapRAID OK on $host"
          tags="white_check_mark"
          body="snapraid-btrfs sync/scrub completed successfully."
          ;;
        *)
          prio=${lib.escapeShellArg notif.ntfy.failurePriority}
          title="SnapRAID FAILED on $host"
          tags="rotating_light,warning"
          body="snapraid-btrfs-sync failed. Recent log:

      $(journalctl -u snapraid-btrfs-sync.service -n 20 --no-pager 2>/dev/null || echo '(journal unavailable)')"
          ;;
      esac

      auth=()
      if [[ -n "''${NTFY_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ''${NTFY_TOKEN}")
      fi

      curl -fsS --max-time 20 "''${auth[@]}" \
        -H "Title: $title" \
        -H "Priority: $prio" \
        -H "Tags: $tags" \
        -d "$body" \
        "$server/$topic" >/dev/null
    '';
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

    verifyMountsBeforeSync = lib.mkOption {
      type = bool;
      default = true;
      description = ''
        Run a pre-flight check (as ExecStartPre) before the scheduled sync that
        verifies every configured data and parity disk is present, mounted, the
        expected filesystem, and (for parity) writable. If any check fails the
        sync unit aborts before SnapRAID runs, preventing a degraded array from
        being synced into parity.
      '';
    };

    notifications = {
      secretsFile = lib.mkOption {
        type = nullOr path;
        default = "/etc/snapraid-btrfs/secrets.env";
        description = ''
          Root-only EnvironmentFile with secrets as KEY=VALUE lines:
          `SMTP_PASSWORD` (for email) and/or `NTFY_TOKEN` (for authenticated
          ntfy). Kept out of the world-readable Nix store and referenced
          optionally, so a missing file degrades gracefully (the run still
          completes; only the notification fails).
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
          description = "SMTP username (password comes from secretsFile as SMTP_PASSWORD).";
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

      ntfy = {
        enable = lib.mkEnableOption "ntfy push notifications (every run, with prioritised failures)";
        server = lib.mkOption {
          type = str;
          default = "https://ntfy.sh";
          description = "ntfy base URL (use your self-hosted server if applicable).";
        };
        topic = lib.mkOption {
          type = str;
          default = "";
          description = "ntfy topic to publish to.";
        };
        notifyOnSuccess = lib.mkOption {
          type = bool;
          default = true;
          description = "Also send a notification after successful runs (not just failures).";
        };
        successPriority = lib.mkOption {
          type = str;
          default = "low";
          description = "ntfy priority for successful runs.";
        };
        failurePriority = lib.mkOption {
          type = str;
          default = "urgent";
          description = "ntfy priority for failed runs / detected errors.";
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
      {
        assertion = !ntfyEnabled || notif.ntfy.topic != "";
        message = "services.snapraid-btrfs.notifications.ntfy requires a topic to be set.";
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

    systemd.services.snapraid-btrfs-sync = {
      description = "Synchronize SnapRAID array using BTRFS snapshots";
      startAt = cfg.syncAt;
      # The runner's SMTP client (Python) needs the system CA bundle to verify
      # STARTTLS under the strict sandbox.
      environment = lib.mkIf emailEnabled {
        SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      };
      unitConfig = lib.mkIf ntfyEnabled (
        {OnFailure = "snapraid-btrfs-notify-failure.service";}
        // lib.optionalAttrs notif.ntfy.notifyOnSuccess {
          OnSuccess = "snapraid-btrfs-notify-success.service";
        }
      );
      serviceConfig =
        {
          Type = "oneshot";
          User = "root";
          Group = "root";
          ExecStartPre =
            lib.optional emailEnabled "${renderRunnerConf}/bin/snapraid-btrfs-render-runner-conf"
            ++ lib.optional cfg.verifyMountsBeforeSync "${preflightScript}/bin/snapraid-btrfs-preflight";
          ExecStart =
            if emailEnabled
            then "${pkgs.snapraid-btrfs-runner}/bin/snapraid-btrfs-runner -c ${runtimeRunnerConf}"
            else "${pkgs.snapraid-btrfs-runner}/bin/snapraid-btrfs-runner";
          RuntimeDirectory = "snapraid-btrfs";
          RuntimeDirectoryMode = "0700";
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
          # AF_INET(6) is required for the runner's SMTP email; otherwise UNIX only.
          RestrictAddressFamilies =
            if emailEnabled
            then "AF_UNIX AF_INET AF_INET6"
            else "AF_UNIX";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = "@system-service";
          SystemCallErrorNumber = "EPERM";
          CapabilityBoundingSet = "";
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadOnlyPaths = ["/etc/snapraid.conf" "/etc/snapper"];
          ReadWritePaths = readWritePaths;
        }
        // lib.optionalAttrs (emailEnabled && hasSecrets) {
          EnvironmentFile = ["-${notif.secretsFile}"];
        };
    };

    systemd.services.snapraid-btrfs-notify-failure = lib.mkIf ntfyEnabled {
      description = "Send ntfy notification for a failed snapraid-btrfs-sync run";
      serviceConfig =
        {
          Type = "oneshot";
          ExecStart = "${ntfyScript}/bin/snapraid-btrfs-notify failure";
        }
        // lib.optionalAttrs hasSecrets {
          EnvironmentFile = ["-${notif.secretsFile}"];
        };
    };

    systemd.services.snapraid-btrfs-notify-success = lib.mkIf (ntfyEnabled && notif.ntfy.notifyOnSuccess) {
      description = "Send ntfy notification for a successful snapraid-btrfs-sync run";
      serviceConfig =
        {
          Type = "oneshot";
          ExecStart = "${ntfyScript}/bin/snapraid-btrfs-notify success";
        }
        // lib.optionalAttrs hasSecrets {
          EnvironmentFile = ["-${notif.secretsFile}"];
        };
    };

    environment.systemPackages = with pkgs; [
      mergerfs
      snapraid-btrfs
      snapraid-btrfs-runner
      btrfs-progs
      initDisksScript
      preflightScript
    ]
    ++ lib.optional ntfyEnabled ntfyScript;
  };
}
