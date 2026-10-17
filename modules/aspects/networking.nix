{
  config,
  hostUserNames,
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
        # Mosh bootstraps over SSH, then needs its UDP range — same tailnet-only
        # scope as SSH (mosh itself is installed by home/common.nix).
        tailscale0 = {
          allowedTCPPorts = [22];
          allowedUDPPortRanges = [
            {
              from = 60000;
              to = 61000;
            }
          ];
        };
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
    # Let the desktop user drive tailscaled without sudo — the shell's
    # omarchy.tailscale bar widget toggles up/down, switches accounts and
    # picks exit nodes as that user. Upstream's install-service script sets
    # this imperatively; here it is re-applied on every boot. Single-user
    # hosts, so the first (only) declared user is the operator.
    extraSetFlags = ["--operator=${builtins.head hostUserNames}"];
  };

  # DNS
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "yes";
      FallbackDNS = ["1.1.1.1" "8.8.8.8"];
    };
  };

  # LAN-addressed NFS mount shared by both kebun hosts. Ordering it after
  # tailscaled supports remote access through an accepted subnet route, but
  # does not itself route 192.168.100.0/24 through Tailscale. Automount avoids
  # a boot hang when the export is unreachable.
  fileSystems."/mnt/tubeinas" = {
    device = "192.168.100.29:/mnt/tank/ivokun";
    fsType = "nfs";
    options = [
      "vers=4"
      "rw"
      "nosuid"
      "nodev"
      "noexec"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=tailscaled.service"
      "x-systemd.after=tailscaled.service"
      "noauto"
      "_netdev"
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = hostUserNames;
    };
  };
}
