{
  config,
  lib,
  pkgs,
  ...
}: {
  networking = {
    networkmanager = {
      enable = true;
      dns = "default";
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [];
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
