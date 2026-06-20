# SnapRAID-BTRFS storage for mason.
# This list is the single source of truth: mounts, snapraid.conf, snapper
# configs, the MergerFS pool, and the `snapraid-btrfs-init-disks` formatter are
# all derived from it. To add/remove a disk, edit this list and rebuild, then
# run `sudo snapraid-btrfs-init-disks` (idempotent; only formats blank drives).
{
  ...
}: {
  services.snapraid-btrfs = {
    enable = true;

    # sdd is parity; sda–sdc are data (all ST8000VN004 8TB).
    disks = [
      {
        name = "disk1";
        role = "data";
        device = "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZBKXSX";
        mountPoint = "/mnt/disk1";
      }
      {
        name = "disk2";
        role = "data";
        device = "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZBJK9W";
        mountPoint = "/mnt/disk2";
      }
      {
        name = "disk3";
        role = "data";
        device = "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZBJY7G";
        mountPoint = "/mnt/disk3";
      }
      {
        name = "parity1";
        role = "parity";
        device = "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZBKHHX";
        mountPoint = "/mnt/parity1";
      }
    ];

    # Notifications. Secrets (SMTP_PASSWORD / NTFY_TOKEN) live in the root-only
    # EnvironmentFile below, NOT in the Nix store. Create it before relying on
    # email/authenticated ntfy:
    #   sudo install -d -m 0700 /etc/snapraid-btrfs
    #   sudo install -m 0600 /dev/null /etc/snapraid-btrfs/secrets.env
    #   # then add:  SMTP_PASSWORD=...   and (optional) NTFY_TOKEN=...
    notifications = {
      secretsFile = "/etc/snapraid-btrfs/secrets.env";

      # Built-in email status report on every run (success + error).
      email = {
        enable = true;
        to = "you@example.com"; # TODO: set
        from = "mason@example.com"; # TODO: set
        host = "smtp.example.com"; # TODO: set
        port = 587;
        user = "mason@example.com"; # TODO: set (password -> secrets.env)
        tls = true;
        ssl = false;
        sendOn = ["success" "error"];
      };

      # Push notification every run; failures get an urgent priority.
      ntfy = {
        enable = true;
        server = "https://ntfy.sh"; # or your self-hosted server
        topic = "mason-snapraid-CHANGE-ME"; # TODO: pick a private, hard-to-guess topic
        notifyOnSuccess = true;
        successPriority = "low";
        failurePriority = "urgent";
      };
    };
  };
}
