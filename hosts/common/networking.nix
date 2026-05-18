{
  config,
  lib,
  pkgs,
  ...
}: {
  networking = {
    # Use iwd standalone for WiFi (required by impala)
    # NetworkManager is intentionally NOT used — it conflicts with iwd
    # when impala tries to manage connections directly via iwd's D-Bus API.
    networkmanager.enable = false;
    wireless.iwd = {
      enable = true;
      settings = {
        Network.EnableIPv6 = true;
      };
    };

    # Use systemd-networkd for wired/DHCP (was previously handled by NetworkManager)
    useNetworkd = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [];
    };
  };

  # systemd-networkd: manage wired connections with DHCP
  systemd.network = {
    enable = true;
    networks = {
      # Wired ethernet — DHCP auto-config
      "10-wired" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = true;
      };
      # WiFi is managed by iwd (iwd handles its own DHCP via systemd-networkd integration)
      "20-wifi" = {
        matchConfig.Name = "wl*";
        networkConfig.DHCP = true;
      };
    };
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # DNS
  services.resolved = {
    enable = true;
    dnssec = "true";
    fallbackDns = ["1.1.1.1" "8.8.8.8"];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true; # Change to false after setup
      PermitRootLogin = "no";
    };
  };

  # Avahi (mDNS for local network discovery)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}