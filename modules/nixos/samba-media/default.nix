{config, lib, pkgs, ...}: let
  mediaPath = "${config.services.snapraid-btrfs.poolMount}/media";
in {
  options.services.samba-media = {
    allowedClients = lib.mkOption {
      type = lib.types.str;
      default = "192.168.0.";
      example = "192.168.0.";
      description = ''
        Space-separated networks/hosts for smb.conf `hosts allow`.
        A trailing dot matches the subnet (e.g. `192.168.0.` → 192.168.0.0/24).
      '';
    };

    shareUser = lib.mkOption {
      type = lib.types.str;
      default = "masons";
      description = "Local user allowed to log in to the share.";
    };
  };

  config = let
    cfg = config.services.samba-media;
  in {
    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "mason media";
          "netbios name" = "mason";
          "hosts allow" = "${cfg.allowedClients} 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
        };
        media = {
          path = mediaPath;
          comment = "Jellyfin media library";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = cfg.shareUser;
          "create mask" = "0664";
          "directory mask" = "0775";
          "force group" = "media";
        };
      };
    };

    users.users.${cfg.shareUser}.extraGroups = ["media"];
    users.groups.media = {};

    environment.systemPackages = [pkgs.samba];
  };
}
