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

    nixos = {
      host,
      config,
      ...
    }: {
      # Both hosts can declare runtime secrets once their real SSH/age
      # recipients are enrolled. Importing the module provisions no secret
      # and does not invent Sakura's still-unknown recipient.
      imports = [inputs.sops-nix.nixosModules.sops];

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
        greeterUser = lib.mkOption {
          type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
          default = "ivokun";
          description = ''
            Login name the SDDM greeter authenticates when SDDM has no
            remembered last user (fresh install, wiped /var/lib/sddm). The
            omarchy theme shows only a password field, so without this
            fallback it submits an empty username and every login fails.
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
        memoryAccountId = lib.mkOption {
          type = lib.types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
          default = "6f67358f-8bbf-48d1-a48f-ec40c3c3fd8d";
          description = ''
            Public Kebun memory account UUID shared by this user's devices.
            This is an identity, not a credential. Changing it against an
            initialized local store fails closed; migration is explicit.
          '';
        };
        memoryActorId = lib.mkOption {
          type = lib.types.strMatching "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
          description = ''
            Public, stable, unique memory actor UUID for this host. Set it
            in the host module, never infer it from a hostname in Home
            Manager. Do not reuse another device's initialized identity.
          '';
        };
        memorySync = lib.mkOption {
          default = {};
          description = "Optional memory replication; local operation is the default.";
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "private HTTPS memory synchronization";
              enrollmentConfirmed = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Explicit operator gate: enable only after the private
                  endpoint, device authorization, backup/restore checks and
                  actual host SOPS recipient enrollment are complete. No
                  recipient, credential or service is provisioned here.
                '';
              };
              url = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "https://[^[:space:]#?@]+");
                default = null;
                description = "Private HTTPS sync endpoint; never put a token in this URL.";
              };
              tokenFile = lib.mkOption {
                type = lib.types.nullOr (lib.types.strMatching "/[^[:space:]]+");
                default = null;
                description = ''
                  Absolute runtime path to the user-readable device token,
                  normally config.sops.secrets.<name>.path after enrollment.
                  This is a string, not a Nix path: the secret must never be
                  copied to the store. An absent runtime file only pauses
                  synchronization; it must not block local readiness.
                '';
              };
            };
          };
        };
      };

      config = {
        assertions = let
          sync = config.kebun.host.memorySync;
        in [
          {
            assertion = !sync.enable || sync.enrollmentConfirmed;
            message = "Memory sync requires explicit kebun.host.memorySync.enrollmentConfirmed after real host SOPS recipient/device enrollment and private endpoint/backup gates; do not fabricate Sakura's age recipient.";
          }
          {
            assertion = !sync.enable || (sync.url != null && sync.tokenFile != null);
            message = "Memory sync requires kebun.host.memorySync.url and a runtime tokenFile path. Keep enable = false for local-only operation.";
          }
          {
            assertion = sync.tokenFile == null || !(lib.hasPrefix builtins.storeDir sync.tokenFile);
            message = "Memory sync tokenFile must point to a runtime secret, never a Nix-store file.";
          }
        ];

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

    nixos.imports = [
      ../hosts/ume
    ];
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
