{
  config,
  hostUserNames,
  lib,
  pkgs,
  ...
}: let
  # The tailnet advertises the home LAN as a subnet route, and with
  # --accept-routes Tailscale's table 52 (rule 5270) shadows the connected
  # route: LAN replies leave via tailscale0 and rpfilter drops inbound LAN
  # traffic (lan-mouse, Calibre, LocalSend). Consult main first, but
  # suppress its default route, so the LAN goes direct when attached and
  # falls through to the subnet route when away.
  lanFirst = {
    To = "192.168.100.0/24";
    Table = "main";
    SuppressPrefixLength = 0;
    Priority = 5200;
  };
in {
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
        routingPolicyRules = [lanFirst];
      };
      # WiFi is managed by iwd (iwd handles its own DHCP via systemd-networkd integration)
      "20-wifi" = {
        matchConfig.Name = "wl*";
        networkConfig.DHCP = true;
        routingPolicyRules = [lanFirst];
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

  # On-demand WireGuard tunnel into 10.42.0.0/16 (split tunnel: only that
  # range is routed through it). autostart = false — nothing brings it up at
  # boot; toggle with `sudo systemctl start|stop wg-quick-wg0`.
  #
  # The private key is NOT in the repo or the store: provision it per host as
  # a root-only file before the first start:
  #   sudo install -m 0600 -o root -g root /dev/stdin /etc/wireguard/wg0.key
  # Both hosts share one peer identity (10.8.0.7), so bring the tunnel up on
  # one host at a time — the server tracks a single endpoint per key.
  networking.wg-quick.interfaces.wg0 = {
    autostart = false;
    address = ["10.8.0.7/32"];
    privateKeyFile = "/etc/wireguard/wg0.key";
    # wg-quick hands this to resolved's resolvconf shim as the exclusive
    # (~.) resolver for the tunnel's lifetime, mirroring `DNS =` in a stock
    # wg-quick config.
    dns = ["10.42.0.2"];
    # Global DNSSEC=yes would turn the remote resolver's private (unsigned)
    # zones into SERVFAILs; relax validation on this link only.
    postUp = "${config.systemd.package}/bin/resolvectl dnssec wg0 no";
    peers = [
      {
        publicKey = "mlz6EXTfNy23PUcAFFUmJ8QnVg4SMrk7B5NjeOXbFVQ=";
        allowedIPs = ["10.42.0.0/16"];
        endpoint = "18.181.132.23:51820";
        persistentKeepalive = 25;
      }
    ];
  };
  environment.systemPackages = [pkgs.wireguard-tools];
  # Root-only home for the out-of-band private key above.
  systemd.tmpfiles.rules = ["d /etc/wireguard 0700 root root -"];
  # Let the desktop user toggle this one unit from an active local session
  # without a password — the bar's wireguard-toggle runs as that user. Same
  # operator scoping as Tailscale's --operator above.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "wg-quick-wg0.service" &&
          ["start", "stop", "restart", "reset-failed"].indexOf(action.lookup("verb")) >= 0 &&
          ${builtins.toJSON hostUserNames}.indexOf(subject.user) >= 0 &&
          subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';

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
