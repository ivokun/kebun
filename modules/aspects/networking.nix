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

      # LocalSend discovery/transfer and printer discovery belong on physical
      # LAN links only. SSH is administrative traffic and is reachable only
      # through the tailnet. Keeping these interface-scoped avoids exposing a
      # future listener merely because it happens to bind 0.0.0.0.
      interfaces = {
        "wl+" = {
          allowedTCPPorts = [53317];
          allowedUDPPorts = [53317 5353];
        };
        "en+" = {
          allowedTCPPorts = [53317];
          allowedUDPPorts = [53317 5353];
        };
        tailscale0.allowedTCPPorts = [22];
      };
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
    settings.Resolve = {
      DNSSEC = "yes";
      FallbackDNS = ["1.1.1.1" "8.8.8.8"];
    };
  };

  # SSH
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = ["ivokun"];
    };
  };
}
