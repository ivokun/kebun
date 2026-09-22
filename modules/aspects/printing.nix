# Printing support (CUPS)
{
  config,
  pkgs,
  ...
}: {
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      hplip
    ];
  };

  # Enable autodiscovery of network printers
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # UDP 5353 is opened only on physical LAN links in networking.nix.
    openFirewall = false;
    denyInterfaces = ["tailscale0" "docker0"];
  };
}
