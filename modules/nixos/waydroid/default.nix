{pkgs, ...}: {
  virtualisation.waydroid = {
    enable = true;
    # Kernel 6.17+ (you're on 7.0) no longer ships ip_tables; use nftables backend
    package = pkgs.waydroid-nftables;
  };

  # Clipboard sharing between host and Android apps
  environment.systemPackages = [pkgs.wl-clipboard];
}
