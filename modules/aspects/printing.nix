# Printing support (CUPS)
#
# One explicitly declared queue for the shared home printer. Its LAN address
# (192.168.100.21) is reserved for it in the router, but its IPP capability
# requests fail, so the queue uses the proven raw socket transport with the
# exact Gutenprint driver instead of relying on IPP/driverless setup.
{
  lib,
  pkgs,
  ...
}: {
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      hplip
    ];

    # CUPS stays on the localhost-only defaults: no shared queue, no firewall
    # port opened. cups-browsed is explicitly off so discovery cannot create
    # broken permanent queues; interactive discovery still works through
    # Avahi/CUPS DNS-SD in the Print Settings UI.
    browsed.enable = false;
  };

  hardware.printers = {
    ensurePrinters = [
      {
        name = "Canon_E470";
        description = "Canon E470";
        location = "Home LAN";
        deviceUri = "socket://192.168.100.21:9100";
        model = "gutenprint.${lib.versions.majorMinor (lib.getVersion pkgs.gutenprint)}://bjc-E470-series/expert";
        ppdOptions = {
          printer-is-shared = "false";
          printer-error-policy = "retry-job";
        };
      }
    ];
    ensureDefaultPrinter = "Canon_E470";
  };

  # Print Settings (GTK CUPS administration) and its D-Bus/udev integration.
  programs.system-config-printer.enable = true;

  # mDNS/DNS-SD for interactive printer discovery in the Print Settings UI
  # (not for cups-browsed queue creation, which stays disabled above).
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # UDP 5353 is opened only on physical LAN links in networking.nix.
    openFirewall = false;
    denyInterfaces = ["tailscale0" "docker0"];
  };
}
