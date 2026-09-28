# Den migration — host aspects & wiring (ADR-0013).
# The former hosts/common modules are plain NixOS modules under aspects/ and
# are captured here as aspect imports. Den context data reaches parametric
# aspect bodies directly; shared plain modules receive deliberate host values
# through _module.args. Home Manager's module args are set in modules/users.nix.
{
  den,
  inputs,
  lib,
  ...
}: let
  sharedHostAspects = [
    den.aspects.host-base
    den.aspects.core
    den.aspects.desktop
    den.aspects.dev
    den.aspects.networking
    den.aspects.printing
    den.aspects.snapper
    den.aspects.shell-entry
  ];
in {
  # ─── Shared host aspects ───
  den.aspects.core.nixos.imports = [
    ./aspects/core.nix
    inputs.nix-index-database.nixosModules.nix-index
  ];
  den.aspects.desktop.nixos.imports = [./aspects/desktop.nix];
  den.aspects.dev.nixos.imports = [./aspects/dev.nix];
  den.aspects.networking.nixos.imports = [./aspects/networking.nix];
  den.aspects.printing.nixos.imports = [./aspects/printing.nix];
  den.aspects.snapper.nixos.imports = [./aspects/snapper.nix];

  # Host-free shell settings from the former hosts/common/users.nix.
  den.aspects.shell-entry.nixos = {
    programs.fish.enable = true;
    programs.zsh.enable = true;
  };

  # ─── Reusable base wiring included by every host aspect ───
  # Hostname, module args, nested Home Manager settings, package overlays and
  # the kebun.* host capability options live here so hosts/<name> aspects
  # declare only their own files and values.
  den.aspects.host-base = {
    includes = [den.batteries.hostname];

    nixos = {host, ...}: {
      # Typed host surface consumed by Home Manager via osConfig — hosts set
      # these in hosts/<name>/default.nix and HM modules branch on them
      # instead of matching on hostName.
      options.kebun.host = {
        isLaptop = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether the host is a battery-powered laptop. Home Manager uses
            this (via osConfig) to emit battery/lid/touchpad/laptop-display
            configuration only where it applies.
          '';
        };
        greeterLayout = lib.mkOption {
          type = lib.types.strMatching "[A-Za-z0-9_-]+";
          default = "us";
          description = ''
            Single XKB keyboard layout for the SDDM greeter session. The
            greeter does not inherit the desktop input config (kebun's
            default is us); individual hosts override it (sakura uses jp).
          '';
        };
        monitorsLua = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Host-provided monitor layout as hl.monitor(...) Lua lines,
            rendered verbatim into ~/.config/hypr/monitors.lua. A host that
            leaves this empty gets kebun's single-preferred-output fallback.
          '';
        };
      };

      config = {
        networking.hostName = host.hostName;

        # NixOS-module fn args consumed by hosts/* and shared plain modules.
        _module.args = {
          inherit inputs;
          hostUserNames = builtins.attrNames host.users;
        };

        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "hm-backup";

        nixpkgs.overlays = [
          (final: prev: {
            deno = prev.deno.overrideAttrs (old: {
              checkFlags =
                (old.checkFlags or [])
                ++ [
                  "--skip"
                  "uv_compat::tests::tty_reset_mode_restores_termios"
                ];
            });
          })
          (import ../lib/opencode-overlay.nix)
        ];
      };
    };
  };

  # ─── Host aspects ───

  # sakura: ThinkPad X13 Gen 1 laptop (AMD Renoir), live since 2026-09-04.
  den.aspects.sakura = {
    includes = sharedHostAspects;

    nixos.imports = [../hosts/sakura];
  };

  # ume: ASRock B550M-ITX/ac desktop (Ryzen 9 5900X, RX 9060 XT) — the
  # current ivokun-htpc hardware, pre-install. Same shared workstation
  # aspects as sakura; machine facts stay in hosts/ume/.
  den.aspects.ume = {
    includes = sharedHostAspects;

    nixos.imports = [../hosts/ume];
  };

  # ─── Entity wiring: hosts, ivokun user with homeManager ───
  den.hosts.x86_64-linux.sakura.users.ivokun = {
    classes = ["homeManager"];
  };

  den.hosts.x86_64-linux.ume.users.ivokun = {
    classes = ["homeManager"];
  };

  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # ─── Defaults (stateVersion) ───
  den.default.nixos.system.stateVersion = "25.05";
  den.default.homeManager.home.stateVersion = "25.05";
}
