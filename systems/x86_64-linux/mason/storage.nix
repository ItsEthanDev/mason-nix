# SnapRAID-BTRFS storage for mason.
# This list is the single source of truth: mounts, snapraid.conf, snapper
# configs, the MergerFS pool, and the `snapraid-btrfs-init-disks` formatter are
# all derived from it. To add/remove a disk, edit this list and rebuild, then
# run `sudo snapraid-btrfs-init-disks` (idempotent; only formats blank drives).
{
  config,
  pkgs,
  ...
}: {
  # 1Password-backed secrets via opnix. The only local secret is the service
  # account token at /etc/opnix-token (set once with `sudo opnix token set`);
  # everything else is pulled from 1Password at boot into root-only files under
  # /var/lib/opnix/secrets. Create matching 1Password items (adjust the
  # references below to your vault/item/field names) before relying on email.
  # Missing token -> email degrades gracefully.
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    # Order the sync unit after secrets are deployed.
    systemdIntegration.services = ["snapraid-btrfs-sync"];
    secrets = {
      snapraidSmtpPassword = {
        reference = "op://Homelab/snapraid-smtp/password";
        mode = "0400";
      };
    };
  };

  # Make the `opnix` CLI available for `opnix token set`.
  environment.systemPackages = [pkgs.opnix];

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

    # Notifications. The SMTP password is pulled from 1Password by opnix into a
    # root-only file (see services.onepassword-secrets above) and referenced
    # here by path, so nothing sensitive lands in the Nix store. The legacy
    # EnvironmentFile is disabled.
    notifications = {
      secretsFile = null;

      # Built-in email status report on every run (success + error).
      email = {
        enable = true;
        to = "shafmasb@gmail.com"; # TODO: set
        from = "mason@snapraidnotification.com"; # TODO: set
        host = "smtp.gmail.com"; # TODO: set
        port = 587;
        user = "shafmasb@gmail.com"; # TODO: set (password -> 1Password)
        tls = true;
        ssl = false;
        sendOn = ["success" "error"];
        passwordFile = config.services.onepassword-secrets.secretPaths.snapraidSmtpPassword;
      };
    };
  };
}
