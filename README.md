# kebun — NixOS config for sakura

Kebun is a NixOS system flake for `sakura` (ThinkPad X13 Gen 1, AMD Renoir
APU) — a single-host, single-user configuration, desktop = kebun's port of
[Omarchy](https://omarchy.org) v4 ("Quattro") to NixOS idioms (QuickShell
shell, Hyprland Lua, palette-driven theming).

Since [ADR-0013](docs/adr/0013-adopt-den-aspect-oriented-framework.md) the
wiring is **aspect-oriented via [Den](https://github.com/denful/den)**:
one aspect per concern, entities declared as data, context delivered as
function args.

## At a glance

Two scopes: `host:sakura` (NixOS) and `user:ivokun` (home-manager, nested).
The host's aspect spine (`networking` → `core` → `dev` → `shell-entry` →
`printing` → `hostname` → `snapper`) mounts via aspect `includes`; the
glue between the scopes is the `host-to-users` policy, the `hm-user-detect`
battery, and the `os-to-host` forward. Graphs are the auto-generated
mermaid sections at the bottom of this page — rendered natively by GitHub
(no build artifacts). Regenerate with `nix run .#update-readme`.

## Commands

```bash
nixos-rebuild build --flake .#sakura   # eval + build without activating
nh os switch .                         # apply (normal path)
nix fmt                                # alejandra formatter
nix run .#update-readme               # regenerate the mermaid graphs section
```

Post-switch verification: `systemctl --failed`,
`systemctl --user --failed`, `journalctl -b -p warning`.

## Layout

| Path | Purpose |
|---|---|
| `modules/den.nix` | Entity declarations (`den.hosts.x86_64-linux.sakura.users.ivokun`), defaults |
| `modules/aspects/*.nix` | NixOS aspects: core, desktop, dev, networking, printing, snapper |
| `modules/users.nix` | The ivokun user aspect (wires `home/**` into `den.aspects.ivokun`) |
| `modules/diagrams-mermaid.nix` | mermaid graph generation into README (den-diagram) |
| `hosts/sakura/` | Host-specific: hardware, LUKS/TPM2, power, NFS, Docker |
| `home/**` | Home-Manager modules (imported untouched into the user aspect) |
| `packages/` | Script derivations, vendored Omarchy env/theme, wordmark, Plymouth |
| `docs/adr/` | Architecture decision records |

## Docs

- [ADR-0013 — Den adoption](docs/adr/0013-adopt-den-aspect-oriented-framework.md)
  (includes the A/B build-equivalence verification)
- [INSTALL.md](INSTALL.md) — full install guide (LUKS + BTRFS + flakes)
- [CLAUDE.md](CLAUDE.md) — agent-facing conventions and gotchas (AGENTS.md symlinks to it)
- Graph packages: `diagrams-mermaid` (raw .mmd), `graph` (text summary for LLMs), `update-readme` (regen README section)
- `docs/omarchy/` — upstream Omarchy research briefs
- `docs/omarchy-parity-backlog.md` — outstanding follow-ups

## Resolution graphs

<!-- BEGIN:AUTO-GENERATED -->

### Overview

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#fffaf3","activationBorderColor":"#9893a5","actorBkg":"#fffaf3","actorBorder":"#797593","actorLineColor":"#797593","actorTextColor":"#575279","background":"#faf4ed","classText":"#575279","clusterBkg":"#fffaf3","clusterBorder":"#9893a5","edgeLabelBackground":"#faf4ed","labelBoxBkgColor":"#fffaf3","labelBoxBorderColor":"#797593","labelTextColor":"#575279","lineColor":"#797593","loopTextColor":"#575279","mainBkg":"#fffaf3","nodeBkg":"#fffaf3","nodeBorder":"#797593","nodeTextColor":"#575279","noteBkgColor":"#fffaf3","noteBorderColor":"#9893a5","noteTextColor":"#575279","pie1":"#b4637a","pie2":"#ea9d34","pie3":"#d7827e","pie4":"#286983","pie5":"#56949f","pie6":"#907aa9","pie7":"#d685af","pie8":"#a9333e","pieLegendTextColor":"#575279","pieOuterStrokeColor":"#9893a5","pieSectionTextColor":"#575279","pieStrokeColor":"#9893a5","pieTitleTextColor":"#575279","primaryBorderColor":"#797593","primaryColor":"#fffaf3","primaryTextColor":"#575279","secondBkg":"#fffaf3","secondaryBorderColor":"#9893a5","secondaryColor":"#fffaf3","secondaryTextColor":"#575279","sequenceNumberColor":"#faf4ed","signalColor":"#797593","signalTextColor":"#575279","tertiaryBorderColor":"#9893a5","tertiaryColor":"#fffaf3","tertiaryTextColor":"#575279","textColor":"#575279","titleColor":"#575279"}}}%%
graph TD
  aspects([aspects]):::root
  core[/"core · shared"\]:::core_c
  desktop[/"desktop · shared"\]:::desktop_c
  dev[/"dev · shared"\]:::dev_c
  ivokun[/"ivokun · host"\]:::ivokun_c
  networking[/"networking · shared"\]:::networking_c
  printing[/"printing · shared"\]:::printing_c
  sakura[/"sakura · host"\]:::sakura_c
  shell_entry[/"shell-entry · shared"\]:::shell_entry_c
  snapper[/"snapper · shared"\]:::snapper_c
  wsl_host_aspect[/"wsl-host-aspect · host"\]:::wsl_host_aspect_c

  aspects --> ivokun
  aspects --> sakura
  aspects --> wsl_host_aspect
  sakura --> core
  sakura --> desktop
  sakura --> dev
  sakura --> networking
  sakura --> printing
  sakura --> snapper
  sakura --> shell_entry

  classDef root fill:#907aa9,stroke:#907aa9,color:#1f1d2e,font-weight:bold
  classDef core_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef desktop_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef dev_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef ivokun_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef networking_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef printing_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef sakura_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef shell_entry_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef snapper_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef wsl_host_aspect_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
```

### Hosts

<details>
<summary>sakura</summary>

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#fffaf3","activationBorderColor":"#9893a5","actorBkg":"#fffaf3","actorBorder":"#797593","actorLineColor":"#797593","actorTextColor":"#575279","background":"#faf4ed","classText":"#575279","clusterBkg":"#fffaf3","clusterBorder":"#9893a5","edgeLabelBackground":"#faf4ed","labelBoxBkgColor":"#fffaf3","labelBoxBorderColor":"#797593","labelTextColor":"#575279","lineColor":"#797593","loopTextColor":"#575279","mainBkg":"#fffaf3","nodeBkg":"#fffaf3","nodeBorder":"#797593","nodeTextColor":"#575279","noteBkgColor":"#fffaf3","noteBorderColor":"#9893a5","noteTextColor":"#575279","pie1":"#b4637a","pie2":"#ea9d34","pie3":"#d7827e","pie4":"#286983","pie5":"#56949f","pie6":"#907aa9","pie7":"#d685af","pie8":"#a9333e","pieLegendTextColor":"#575279","pieOuterStrokeColor":"#9893a5","pieSectionTextColor":"#575279","pieStrokeColor":"#9893a5","pieTitleTextColor":"#575279","primaryBorderColor":"#797593","primaryColor":"#fffaf3","primaryTextColor":"#575279","secondBkg":"#fffaf3","secondaryBorderColor":"#9893a5","secondaryColor":"#fffaf3","secondaryTextColor":"#575279","sequenceNumberColor":"#faf4ed","signalColor":"#797593","signalTextColor":"#575279","tertiaryBorderColor":"#9893a5","tertiaryColor":"#fffaf3","tertiaryTextColor":"#575279","textColor":"#575279","titleColor":"#575279"}}}%%
graph LR
  sakura([sakura]):::root

  subgraph ctx_user_ivokun["user: ivokun"]
  _policy_hm_user_detect__0_["<policy:hm-user-detect>[0]"]:::_policy_hm_user_detect__0__c
  default_user_ivokun["default"]:::default_user_ivokun_c
  den__batteries__define_user[/"batteries/define-user"\]:::den__batteries__define_user_c
  den__batteries__define_user__ivokun_sakura{{"batteries/define-user/ivokun@sakura"}}:::den__batteries__define_user__ivokun_sakura_c
  hm_user_detect["hm-user-detect"]:::hm_user_detect_c
  ivokun{{"ivokun"}}:::ivokun_c
  os_to_host_user_ivokun["os-to-host"]:::os_to_host_user_ivokun_c
  den__batteries__primary_user_ivokun_sakura_{{"batteries/primary-user(ivokun@sakura)"}}:::den__batteries__primary_user_ivokun_sakura__c
  user["user"]:::user_c
  user_to_host["user-to-host"]:::user_to_host_c
  user__resolve_user_["user/resolve(user)"]:::user__resolve_user__c
  den__batteries__define_user --> den__batteries__define_user__ivokun_sakura
  ivokun --> den__batteries__define_user
  ivokun --> den__batteries__primary_user_ivokun_sakura_
  user --> _policy_hm_user_detect__0_
  user --> default_user_ivokun
  user --> ivokun
  user --> user__resolve_user_
  end
  subgraph ctx_host_sakura["host: sakura"]
  core["core"]:::core_c
  default_host_sakura["default"]:::default_host_sakura_c
  desktop["desktop"]:::desktop_c
  dev["dev"]:::dev_c
  host["host"]:::host_c
  host_to_hm_users["host-to-hm-users"]:::host_to_hm_users_c
  host_to_users["host-to-users"]:::host_to_users_c
  host__resolve_host_["host/resolve(host)"]:::host__resolve_host__c
  den__batteries__hostname[/"batteries/hostname"\]:::den__batteries__hostname_c
  den__batteries__hostname__os{{"batteries/hostname/os"}}:::den__batteries__hostname__os_c
  insecure_predicate["insecure-predicate"]:::insecure_predicate_c
  insecure_predicate__os{{"insecure-predicate/os"}}:::insecure_predicate__os_c
  insecure_predicate__user{{"insecure-predicate/user"}}:::insecure_predicate__user_c
  networking["networking"]:::networking_c
  os_to_host_host_sakura["os-to-host"]:::os_to_host_host_sakura_c
  printing["printing"]:::printing_c
  shell_entry["shell-entry"]:::shell_entry_c
  snapper["snapper"]:::snapper_c
  unfree_predicate["unfree-predicate"]:::unfree_predicate_c
  unfree_predicate__os{{"unfree-predicate/os"}}:::unfree_predicate__os_c
  unfree_predicate__user{{"unfree-predicate/user"}}:::unfree_predicate__user_c
  default_host_sakura --> insecure_predicate
  default_host_sakura --> unfree_predicate
  den__batteries__hostname --> den__batteries__hostname__os
  host --> default_host_sakura
  host --> host__resolve_host_
  host --> sakura
  insecure_predicate --> insecure_predicate__os
  insecure_predicate --> insecure_predicate__user
  sakura --> core
  sakura --> desktop
  sakura --> dev
  sakura --> den__batteries__hostname
  sakura --> networking
  sakura --> printing
  sakura --> shell_entry
  sakura --> snapper
  unfree_predicate --> unfree_predicate__os
  unfree_predicate --> unfree_predicate__user
  end


  classDef root fill:#907aa9,stroke:#907aa9,color:#1f1d2e,font-weight:bold
  classDef _policy_hm_user_detect__0__c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef core_c fill:#d685af,stroke:#d685af,color:#1f1d2e,stroke-width:3px
  classDef default_host_sakura_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef default_user_ivokun_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef den__batteries__define_user_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef den__batteries__define_user__ivokun_sakura_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef desktop_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef dev_c fill:#d685af,stroke:#d685af,color:#1f1d2e,stroke-width:3px
  classDef hm_user_detect_c fill:#b4637a,stroke:#b4637a,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef host_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef host_to_hm_users_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef host_to_users_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef host__resolve_host__c fill:#fffaf3,stroke:#9893a5,color:#575279,stroke-dasharray: 2 2,stroke-width:1px
  classDef den__batteries__hostname_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef den__batteries__hostname__os_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef insecure_predicate_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef insecure_predicate__os_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef insecure_predicate__user_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef ivokun_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef networking_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef os_to_host_host_sakura_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef os_to_host_user_ivokun_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef den__batteries__primary_user_ivokun_sakura__c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef printing_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef sakura_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef shell_entry_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:3px
  classDef snapper_c fill:#d685af,stroke:#d685af,color:#1f1d2e,stroke-width:3px
  classDef unfree_predicate_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef unfree_predicate__os_c fill:#d685af,stroke:#d685af,color:#1f1d2e,stroke-width:2px
  classDef unfree_predicate__user_c fill:#d685af,stroke:#d685af,color:#1f1d2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef user_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef user_to_host_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef user__resolve_user__c fill:#fffaf3,stroke:#9893a5,color:#575279,stroke-dasharray: 2 2,stroke-width:1px
style ctx_user_ivokun fill:#fffaf3,stroke:#9893a5,stroke-width:2px
style ctx_host_sakura fill:#fffaf3,stroke:#9893a5,stroke-width:2px
```

</details>

### Home Manager

<details>
<summary>ivokun@sakura</summary>

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#fffaf3","activationBorderColor":"#9893a5","actorBkg":"#fffaf3","actorBorder":"#797593","actorLineColor":"#797593","actorTextColor":"#575279","background":"#faf4ed","classText":"#575279","clusterBkg":"#fffaf3","clusterBorder":"#9893a5","edgeLabelBackground":"#faf4ed","labelBoxBkgColor":"#fffaf3","labelBoxBorderColor":"#797593","labelTextColor":"#575279","lineColor":"#797593","loopTextColor":"#575279","mainBkg":"#fffaf3","nodeBkg":"#fffaf3","nodeBorder":"#797593","nodeTextColor":"#575279","noteBkgColor":"#fffaf3","noteBorderColor":"#9893a5","noteTextColor":"#575279","pie1":"#b4637a","pie2":"#ea9d34","pie3":"#d7827e","pie4":"#286983","pie5":"#56949f","pie6":"#907aa9","pie7":"#d685af","pie8":"#a9333e","pieLegendTextColor":"#575279","pieOuterStrokeColor":"#9893a5","pieSectionTextColor":"#575279","pieStrokeColor":"#9893a5","pieTitleTextColor":"#575279","primaryBorderColor":"#797593","primaryColor":"#fffaf3","primaryTextColor":"#575279","secondBkg":"#fffaf3","secondaryBorderColor":"#9893a5","secondaryColor":"#fffaf3","secondaryTextColor":"#575279","sequenceNumberColor":"#faf4ed","signalColor":"#797593","signalTextColor":"#575279","tertiaryBorderColor":"#9893a5","tertiaryColor":"#fffaf3","tertiaryTextColor":"#575279","textColor":"#575279","titleColor":"#575279"}}}%%
graph LR
  ivokun([ivokun]):::root

  subgraph ctx_user_ivokun["user: ivokun"]
  _policy_hm_user_detect__0_["<policy:hm-user-detect>[0]"]:::_policy_hm_user_detect__0__c
  n_default["default"]:::n_default_c
  den__batteries__define_user[/"batteries/define-user"\]:::den__batteries__define_user_c
  den__batteries__define_user__ivokun_sakura{{"batteries/define-user/ivokun@sakura"}}:::den__batteries__define_user__ivokun_sakura_c
  hm_user_detect["hm-user-detect"]:::hm_user_detect_c
  os_to_host["os-to-host"]:::os_to_host_c
  den__batteries__primary_user_ivokun_sakura_{{"batteries/primary-user(ivokun@sakura)"}}:::den__batteries__primary_user_ivokun_sakura__c
  user["user"]:::user_c
  user_to_host["user-to-host"]:::user_to_host_c
  user__resolve_user_["user/resolve(user)"]:::user__resolve_user__c
  den__batteries__define_user --> den__batteries__define_user__ivokun_sakura
  ivokun --> den__batteries__define_user
  ivokun --> den__batteries__primary_user_ivokun_sakura_
  user --> _policy_hm_user_detect__0_
  user --> n_default
  user --> ivokun
  user --> user__resolve_user_
  end


  classDef root fill:#907aa9,stroke:#907aa9,color:#1f1d2e,font-weight:bold
  classDef _policy_hm_user_detect__0__c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef n_default_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef den__batteries__define_user_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef den__batteries__define_user__ivokun_sakura_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef hm_user_detect_c fill:#b4637a,stroke:#b4637a,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef ivokun_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef os_to_host_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef den__batteries__primary_user_ivokun_sakura__c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef user_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:3px
  classDef user_to_host_c fill:#a9333e,stroke:#a9333e,color:#1f1d2e,stroke-width:2px,stroke-dasharray: 8 4
  classDef user__resolve_user__c fill:#fffaf3,stroke:#9893a5,color:#575279,stroke-dasharray: 2 2,stroke-width:1px
style ctx_user_ivokun fill:#fffaf3,stroke:#9893a5,stroke-width:2px
```

</details>

### Dependencies

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#fffaf3","activationBorderColor":"#9893a5","actorBkg":"#fffaf3","actorBorder":"#797593","actorLineColor":"#797593","actorTextColor":"#575279","background":"#faf4ed","classText":"#575279","clusterBkg":"#fffaf3","clusterBorder":"#9893a5","edgeLabelBackground":"#faf4ed","labelBoxBkgColor":"#fffaf3","labelBoxBorderColor":"#797593","labelTextColor":"#575279","lineColor":"#797593","loopTextColor":"#575279","mainBkg":"#fffaf3","nodeBkg":"#fffaf3","nodeBorder":"#797593","nodeTextColor":"#575279","noteBkgColor":"#fffaf3","noteBorderColor":"#9893a5","noteTextColor":"#575279","pie1":"#b4637a","pie2":"#ea9d34","pie3":"#d7827e","pie4":"#286983","pie5":"#56949f","pie6":"#907aa9","pie7":"#d685af","pie8":"#a9333e","pieLegendTextColor":"#575279","pieOuterStrokeColor":"#9893a5","pieSectionTextColor":"#575279","pieStrokeColor":"#9893a5","pieTitleTextColor":"#575279","primaryBorderColor":"#797593","primaryColor":"#fffaf3","primaryTextColor":"#575279","secondBkg":"#fffaf3","secondaryBorderColor":"#9893a5","secondaryColor":"#fffaf3","secondaryTextColor":"#575279","sequenceNumberColor":"#faf4ed","signalColor":"#797593","signalTextColor":"#575279","tertiaryBorderColor":"#9893a5","tertiaryColor":"#fffaf3","tertiaryTextColor":"#575279","textColor":"#575279","titleColor":"#575279"}}}%%
graph TD
  aspects([aspects]):::root
  core[/"core · shared"\]:::core_c
  desktop[/"desktop · shared"\]:::desktop_c
  dev[/"dev · shared"\]:::dev_c
  ivokun[/"ivokun · host"\]:::ivokun_c
  networking[/"networking · shared"\]:::networking_c
  printing[/"printing · shared"\]:::printing_c
  sakura[/"sakura · host"\]:::sakura_c
  shell_entry[/"shell-entry · shared"\]:::shell_entry_c
  snapper[/"snapper · shared"\]:::snapper_c
  wsl_host_aspect[/"wsl-host-aspect · host"\]:::wsl_host_aspect_c

  aspects --> ivokun
  aspects --> sakura
  aspects --> wsl_host_aspect
  sakura --> core
  sakura --> desktop
  sakura --> dev
  sakura --> networking
  sakura --> printing
  sakura --> snapper
  sakura --> shell_entry

  classDef root fill:#907aa9,stroke:#907aa9,color:#1f1d2e,font-weight:bold
  classDef core_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef desktop_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef dev_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef ivokun_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef networking_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef printing_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef sakura_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
  classDef shell_entry_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef snapper_c fill:#ea9d34,stroke:#ea9d34,color:#1f1d2e,stroke-width:2px
  classDef wsl_host_aspect_c fill:#907aa9,stroke:#907aa9,color:#1f1d2e,stroke-width:2px
```

<!-- END:AUTO-GENERATED -->
