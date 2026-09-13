# Class Slice: nixos: sakura

![nixos slice](./class-nixos.mmd.svg)

```mermaid
%%{init: {"elk":{"mergeEdges":true,"nodePlacementStrategy":"BRANDES_KOEPF"},"flowchart":{"wrappingWidth":600},"layout":"elk","theme":"base","themeVariables":{"activationBkgColor":"#fffaf3","activationBorderColor":"#9893a5","actorBkg":"#fffaf3","actorBorder":"#797593","actorLineColor":"#797593","actorTextColor":"#575279","background":"#faf4ed","classText":"#575279","clusterBkg":"#fffaf3","clusterBorder":"#9893a5","edgeLabelBackground":"#faf4ed","labelBoxBkgColor":"#fffaf3","labelBoxBorderColor":"#797593","labelTextColor":"#575279","lineColor":"#797593","loopTextColor":"#575279","mainBkg":"#fffaf3","nodeBkg":"#fffaf3","nodeBorder":"#797593","nodeTextColor":"#575279","noteBkgColor":"#fffaf3","noteBorderColor":"#9893a5","noteTextColor":"#575279","pie1":"#b4637a","pie2":"#ea9d34","pie3":"#d7827e","pie4":"#286983","pie5":"#56949f","pie6":"#907aa9","pie7":"#ea9d34","pie8":"#cecacd","pieLegendTextColor":"#575279","pieOuterStrokeColor":"#9893a5","pieSectionTextColor":"#575279","pieStrokeColor":"#9893a5","pieTitleTextColor":"#575279","primaryBorderColor":"#797593","primaryColor":"#fffaf3","primaryTextColor":"#575279","secondBkg":"#fffaf3","secondaryBorderColor":"#9893a5","secondaryColor":"#fffaf3","secondaryTextColor":"#575279","sequenceNumberColor":"#faf4ed","signalColor":"#797593","signalTextColor":"#575279","tertiaryBorderColor":"#9893a5","tertiaryColor":"#fffaf3","tertiaryTextColor":"#575279","textColor":"#575279","titleColor":"#575279"}}}%%
graph LR
  sakura([sakura]):::root

  subgraph ctx_user_ivokun["user: ivokun"]
  den__batteries__define_user[/"batteries/define-user"\]:::den__batteries__define_user_c
  den__batteries__define_user__ivokun_sakura{{"batteries/define-user/ivokun@sakura"}}:::den__batteries__define_user__ivokun_sakura_c
  ivokun{{"ivokun"}}:::ivokun_c
  den__batteries__primary_user_ivokun_sakura_{{"batteries/primary-user(ivokun@sakura)"}}:::den__batteries__primary_user_ivokun_sakura__c
  den__batteries__define_user --> den__batteries__define_user__ivokun_sakura
  ivokun --> den__batteries__define_user
  ivokun --> den__batteries__primary_user_ivokun_sakura_
  end
  subgraph ctx_host_sakura["host: sakura"]
  core["core"]:::core_c
  desktop["desktop"]:::desktop_c
  dev["dev"]:::dev_c
  den__batteries__hostname[/"batteries/hostname"\]:::den__batteries__hostname_c
  den__batteries__hostname__os{{"batteries/hostname/os"}}:::den__batteries__hostname__os_c
  insecure_predicate["insecure-predicate"]:::insecure_predicate_c
  insecure_predicate__os{{"insecure-predicate/os"}}:::insecure_predicate__os_c
  networking["networking"]:::networking_c
  printing["printing"]:::printing_c
  shell_entry["shell-entry"]:::shell_entry_c
  snapper["snapper"]:::snapper_c
  unfree_predicate["unfree-predicate"]:::unfree_predicate_c
  unfree_predicate__os{{"unfree-predicate/os"}}:::unfree_predicate__os_c
  den__batteries__hostname --> den__batteries__hostname__os
  insecure_predicate --> insecure_predicate__os
  sakura --> core
  sakura --> desktop
  sakura --> dev
  sakura --> den__batteries__hostname
  sakura --> networking
  sakura --> printing
  sakura --> shell_entry
  sakura --> snapper
  unfree_predicate --> unfree_predicate__os
  end


  classDef root fill:#907aa9,stroke:#907aa9,color:#cecacd,font-weight:bold
  classDef core_c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:3px
  classDef den__batteries__define_user_c fill:#cecacd,stroke:#cecacd,color:#cecacd,stroke-width:3px
  classDef den__batteries__define_user__ivokun_sakura_c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:2px
  classDef desktop_c fill:#cecacd,stroke:#cecacd,color:#cecacd,stroke-width:3px
  classDef dev_c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:3px
  classDef den__batteries__hostname_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:3px
  classDef den__batteries__hostname__os_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:2px
  classDef insecure_predicate_c fill:#cecacd,stroke:#cecacd,color:#cecacd,stroke-width:3px
  classDef insecure_predicate__os_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:2px
  classDef ivokun_c fill:#cecacd,stroke:#cecacd,color:#cecacd,stroke-width:3px
  classDef networking_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:3px
  classDef den__batteries__primary_user_ivokun_sakura__c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:2px
  classDef printing_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:3px
  classDef sakura_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:3px
  classDef shell_entry_c fill:#907aa9,stroke:#907aa9,color:#cecacd,stroke-width:3px
  classDef snapper_c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:3px
  classDef unfree_predicate_c fill:#cecacd,stroke:#cecacd,color:#cecacd,stroke-width:3px
  classDef unfree_predicate__os_c fill:#ea9d34,stroke:#ea9d34,color:#cecacd,stroke-width:2px
style ctx_user_ivokun fill:#fffaf3,stroke:#9893a5,stroke-width:2px
style ctx_host_sakura fill:#fffaf3,stroke:#9893a5,stroke-width:2px
```
