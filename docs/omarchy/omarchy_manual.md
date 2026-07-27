# Omarchy Manual — Deep-Read Research Brief

**Source:** https://learn.omacom.io/2/the-omarchy-manual (plus all 48 sub-pages)
**Accessed:** 2026-07-27
**Version described:** The manual describes the **Omarchy 3** era — it states "As of Omarchy 3, there's built-in support for Intel Macs"[^40^] and notes the Limine bootloader "has been the default since Omarchy 2.0"[^43^]. No exact point-release (e.g. 3.x) is stated anywhere in the manual. **Precise version number: not found in manual.**
**Authorship:** The manual index page is titled "The Omarchy Manual — DHH"[^1^].

---

## 0. Manual structure (full page inventory)

The manual index[^1^] is a list view of 48 sub-pages. Section-group pages ("The Basics", "The Applications", "Configuration", "The Rest") contain only a heading; all content lives in leaf pages. Sidebar order on every page:

1. Welcome to Omarchy — `/91/welcome-to-omarchy`[^2^]
2. **The Basics** (group) — Getting Started `/50`[^3^], Navigation `/51`[^4^], Themes `/52`[^5^], Hotkeys `/53`[^6^], Universal Clipboard & History `/105`[^7^], Reminders `/117`[^8^], Notices `/119`[^9^], Text Extraction & Dictation `/116`[^10^], Omarchy CLI `/115`[^11^]
3. **The Applications** (group) — Terminal `/106`[^12^], Neovim `/56`[^13^], AI `/107`[^14^], Development Tools `/62`[^15^], Shell Tools `/57`[^16^], Shell Functions `/58`[^17^], TUIs `/59`[^18^], GUIs `/60`[^19^], Commercial `/61`[^20^], Web Apps `/63`[^21^], Gaming `/71`[^22^], Filling out PDFs `/54`[^23^], Windows VM `/100`[^24^]
4. Other Packages `/66`[^25^]
5. **Configuration** (group) — Updates `/68`[^26^], Dotfiles `/65`[^27^], Monitors `/86`[^28^], Keyboard/Mouse/Trackpad `/78`[^29^], System Sleep `/103`[^30^], Hardware Authentication `/77`[^31^], Fonts `/94`[^32^], Backgrounds `/89`[^33^], Prompt `/95`[^34^], Branding `/118`[^35^], Common Tweaks `/102`[^36^], Extra Themes `/90`[^37^], Making Your Own Theme `/92`[^38^]
6. **The Rest** (group) — Manual Installation `/96`[^39^], Mac Support `/97`[^40^], Troubleshooting `/88`[^41^], FAQ `/67`[^42^], System Snapshots `/101`[^43^], Security `/93`[^44^], Omarchy on... `/79`[^45^]

Coverage check: every `href` matching `/2/the-omarchy-manual/<n>/<slug>` in the index HTML was fetched and read (48/48). No orphan pages found.

---

## 1. Philosophy / "What is Omarchy"

Verbatim core framing:[^2^]

> "Omarchy is an omakase Linux distribution based on Arch and the tiling window manager Hyprland. It ships with everything a modern software developer needs to be productive immediately from Neovim (btw) to Spotify, Chromium to Typora, and Alacritty to LibreOffice. Hell, even Zoom is there!"

> "This isn't just a grab bag of preinstalled packages, though. It's a complete system designed with both aesthetics and productivity in mind. Because a *beautiful* system is a *motivating* system, and productivity has always been downstream from motivation. There's zero bloat here: Just everything I use."

> "Omarchy isn't like Windows and it's not like macOS either. It's not trying to be as familiar as possible. It's trying to be beautiful and *better*. Embrace the Linux-ness of it all. Manually editing some config files, sure. Heavy on the terminal, definitely."[^2^]

- "Omakase" links to a separate Omacom manual essay ("omakase computing")[^2^] — i.e., chef's-choice curation by DHH.
- Keyboard-first workflow dogma: "Everything in Omarchy happens via the keyboard — *EVERYTHING!* When the system first starts, you literally can't do a thing with the mouse alone."[^4^]
- Tiling-first: default Hyprland layout is **dwindle** — "It keeps all the windows you open on a single workspace visible at all time, even if it has to shrink them down." An opt-in **scrolling** layout exists (`Super + L` per workspace, or `general { layout = scrolling }` in `~/.config/hypr/looknfeel.conf`).[^4^]
- Security posture: "meant to be an operating system that you can use to do *Real Work* in the *Real World*. Where losing a laptop can't lead to a security emergency."[^44^]
- Not FOSS-absolutist: "Omarchy is mostly focused on providing free, open source software, but it's not religious about it. Sometimes the best solution is a commercial offering, and that's just fine."[^20^]
- On acquiring the taste: "developing an eye for the beauty of a TUI-heavy, theme-delighted, tiling-window-managed system like Omarchy can be an acquired taste."[^2^]
- Update philosophy: four channels (stable / RC / edge / dev); stable tracks official releases plus a curated Arch mirror "running one month behind the latest, so we can catch any new incompatibilities... before they cause problems." Direct `pacman -Syu`/`yay -Syu` is discouraged because config migrations would be missed.[^26^]

---

## 2. Installation & first-run flow

### 2.1 ISO install (default path)[^3^]
1. Download the Omarchy ISO from https://omarchy.org/; write to USB with balenaEtcher (Mac/Windows) or caligula (Linux).
2. "**You must turn off Secure Boot and/or TPM in the BIOS.**"[^3^]
3. Boot off the stick; answer the configuration questions and confirm.
4. Select a drive — **the install wipes the drive and uses full-disk encryption by default**; designed for a dedicated drive (dual-boot requires two disks unless using manual install).
5. "It takes between 2-10 minutes, depending on the speed of your computer."[^3^]

Notes:[^3^]
- Bluetooth keyboards can't enter the disk-decryption password at boot — wired or 2.4 GHz keyboard required.
- No-encryption install possible: hit `Ctrl + C` at the disk-formatting confirmation.
- Help channel: `#omarchy-help` on the community Discord.

### 2.2 Manual installation (archinstall path)[^39^]
For special cases (Asahi Alarm on M-series Macs, single-drive dual-boot). Steps: vanilla Arch ISO → `iwctl` for wifi → `archinstall` with these choices (verbatim table):[^39^]

| Section | Option |
| --- | --- |
| Mirrors and repositories | Select regions > Your country |
| Disk configuration | Partitioning > Default partitioning layout > Select disk (with space + return) |
| Disk > File system | btrfs (default structure: yes + use compression) |
| Disk > Disk encryption | Encryption type: LUKS + Encryption password + Partitions (select the one) |
| Hostname | Give your computer a name |
| Bootloader | Limine |
| Authentication > Root password | Set yours |
| Authentication > User account | Add a user > Superuser: Yes > Confirm and exit |
| Applications > Audio | pipewire |
| Network configuration | Copy ISO network config |
| Timezone | Set yours |

- Disk encryption is **mandatory by design**: "The setup relies exclusively on disk encryption to secure your device, as it'll auto-login the user after the disk has been decrypted at boot."[^39^]
- After reboot + login: `curl -fsSL https://omarchy.org/install | bash`. It asks for sudo, then name + email (used to preconfigure git `user.name`/`user.email` and the `CapsLock Space E` / `CapsLock Space N` auto-expansions). Runs 5–30 minutes, then asks permission to reboot.[^39^]

### 2.3 Mac install (Intel only, Omarchy 3+)[^40^]
Omarchy must be the only OS (drive wiped). Requires disabling Apple Secure Boot via Recovery (Cmd-R → Startup Security Utility → "No Security" + "Allow booting from external media"), then boot the USB via Option key → orange EFI Boot. Known limitations catalogued for T1-chip (Touch Bar dead, no sound) and T2-chip devices (model list on page). M-series not directly supported. Claimed "36% performance gains on a 2019 MacBook Pro just by installing Omarchy."[^40^]

### 2.4 Post-install / first-run conventions
- First boot: nothing is mouse-operable; `Super + Space` (launcher) and `Super + Alt + Space` (Omarchy Menu) are the two entry points.[^4^]
- `Super + K` shows all main keyboard bindings.[^6^]
- Defaults can be set under `Setup > Defaults` (e.g. `Setup > Defaults > Editor`).[^15^][^42^]

---

## 3. Workflow conventions (navigation model)[^4^]

- Applications bound to direct hotkeys; launcher is not the primary interface.
- Tiling demo flow: terminal `Super + Return`, browser `Super + Shift + Return`; `Super + J` toggles split direction; `Super + Shift + Arrow` swaps windows; `Super + T` toggles floating; `Super + Arrow` moves focus (cursor centers on new window).
- Workspaces: `Super + Shift + 2` moves focused window to workspace 2; `Super + Shift + Alt + 2` moves without following.
- Mouse: hold `Super` + left-drag to move windows; `Super` + right-drag to resize.
- Close window `Super + W`; close all windows `Ctrl + Alt + Delete`.
- Fullscreen variants: `Super + F` fullscreen; `Super + Alt + F` full-width (keeps top bar); `Super + Ctrl + F` fullscreen within window ("good for YouTube").
- **Grouping:** `Super + G` toggles group; new windows join active group; `Super + Ctrl + Arrows` or `Super + Alt + 1/2/3/4` navigates inside; `Super + Alt + G` moves a window out; `Super + Alt + Arrows` pulls outside windows in.[^4^]
- **Popping (sticky float):** `Super + O` pins a floating window that follows across workspaces ("great for video players").[^4^]
- **Scratchpad:** special overlay workspace; `Super + S` shows it, `Super + Alt + S` sends window there.[^4^]
- Layouts: dwindle (default) vs scrolling (`Super + L` toggles per workspace).[^4^]

---

## 4. Complete hotkey documentation (verbatim tables)

Source: Hotkeys page[^6^] unless noted. Intro line: "You can see all the main keyboard bindings with `Super + K`."[^6^]

### 4.1 Navigating[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Space` | Application launcher |
| `Super + Alt + Space` | Omarchy control menu |
| `Super + Escape` | System menu (suspend, restart, etc) |
| `Super + Ctrl + L` | Lock computer |
| `Super + W` | Close window |
| `Ctrl + Alt + Del` | Close all windows |
| `Super + T` | Toggle window between tiling/floating |
| `Super + J` | Toggle window position (horizontal/vertical) |
| `Super + O` | Toggle popping window into sticky'n'floating |
| `Super + L` | Toggle between dwindle and scrolling layout |
| `Super + P` | Toggle pseudo window style (natural v stretch) |
| `Super + F` | Go full screen |
| `Super + Alt + F` | Go full width |
| `Super + Ctrl + F` | Go full screen inside window |
| `Super + 1/2/3/4` | Jump to specific workspace |
| `Super + Tab` | Jump to next workspace |
| `Super + Shift + Tab` | Jump to previous workspace |
| `Super + Ctrl + Tab` | Jump to former workspace |
| `Super + Shift + 1/2/3/4` | Move window to workspace |
| `Super + Shift + Alt + 1/2/3/4` | Move window to workspace without following |
| `Super + Shift + Alt + Arrows` | Move workspaces to directional monitor |
| `Super + Arrow` | Move focus to window in direction of arrow |
| `Super + Shift + Arrow` | Swap window with another in direction of arrow |
| `Super + Equal` | Grow windows to the left |
| `Super + Minus` | Grow windows to the right |
| `Super + Shift + Equal` | Grow windows to the bottom |
| `Super + Shift + Minus` | Grow windows to the top |
| `Super + Left Mouse` | Drag window around |
| `Super + Right Mouse` | Resize window |
| `Super + Scroll Wheel` | Scroll through workspaces |
| `Super + G` | Toggle window grouping |
| `Super + Alt + G` | Move window out of grouping |
| `Super + Alt + Tab` | Cycle between windows in grouping |
| `Super + Alt + 1/2/3/4` | Jump to specific window in grouping |
| `Super + Alt + Arrow` | Move window into grouping in direction of arrow |
| `Super + Ctrl + Arrow` | Move between windows inside a tiling group |
| `Super + S` | Show scratchpad workspace overlay |
| `Super + Alt + S` | Move window to scratchpad workspace |
| `Super + Ctrl + Z` | Zoom in on screen (repeat for more zoom) |
| `Super + Ctrl + Alt + Z` | Zoom fully out from screen |
| `Super + /` | Cycle forward through monitor scaling options |
| `Super + Alt + /` | Cycle backward through monitor scaling options |
| `Alt + Tab` | Cycle forward through windows on the active workspace |
| `Alt + Shift + Tab` | Cycle backward through windows on the active workspace |
| `Ctrl + Alt + Tab` | Cycle focus forward through monitors |
| `Ctrl + Alt + Shift + Tab` | Cycle focus backwards through monitors |

### 4.2 System controls[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + A` | Audio controls (wiremix) |
| `Super + Ctrl + B` | Bluetooth controls (bluetui) |
| `Super + Ctrl + W` | Wifi controls (impala) |
| `Super + Ctrl + S` | Share menu (via LocalSend) |
| `Super + Ctrl + T` | Activity (btop) |
| `Super + Ctrl + C` | Capture controls (screenshot/-recording/picker) |
| `Super + Ctrl + O` | Toggle menu |
| `Super + Ctrl + H` | Hardware menu |
| `Super + Ctrl + .` | Transcoding menu |

### 4.3 Adjustments (verbatim — note apparent typo)[^6^]

| Hotkey | Function |
| --- | --- |
| `Shift + Brightness Up` | Maximum screen brightness |
| `Shift + Brightness Up` | Minimum screen brightness |
| `Alt + Brightness Up/Down` | Precise 1% brightness changes |
| `Alt + Volume Up/Down` | Precise 1% volume changes |

(The second row presumably means `Shift + Brightness Down`; the manual prints "Up" twice — reproduced verbatim. Also per Monitors page: brightness keys work normally, Shift = max/min.[^28^])

### 4.4 Launching apps[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Return` | Terminal |
| `Super + Alt + Return` | Tmux terminal |
| `Super + Shift + Return` | Browser |
| `Super + Shift + Alt + B` | Browser (private/incognito) |
| `Super + Shift + F` | File manager |
| `Super + Shift + Alt + F` | File manager in cwd of terminal |
| `Super + Shift + M` | Music (Spotify) |
| `Super + Shift + Alt + M` | Music (cliamp) |
| `Super + Shift + /` | Password manager (1password) |
| `Super + Shift + N` | Neovim |
| `Super + Shift + C` | Calendar (HEY) |
| `Super + Shift + E` | Email (HEY) |
| `Super + Shift + A` | AI (ChatGPT) |
| `Super + Shift + Alt + A` | AI (Grok) |
| `Super + Shift + G` | Messenger (Signal) |
| `Super + Shift + P` | Google Photos |
| `Super + Shift + Alt + G` | Messenger (WhatsApp) |
| `Super + Shift + Ctrl + G` | Messenger (Google) |
| `Super + Shift + D` | Docker (LazyDocker) |
| `Super + Shift + O` | Obsidian |
| `Super + Shift + W` | Writing (Typora) |
| `Super + Shift + X` | X |
| `Super + Shift + Alt + X` | X Compose |
| `Super + Shift + Y` | YouTube |

"Change/add bindings in `~/.config/hypr/bindings.conf`."[^6^]

⚠ Cross-page discrepancy: the Web Apps page says "You can start WhatsApp using `Super + Ctrl + G`"[^21^] — conflicts with the hotkey table above (`Super + Shift + Alt + G`). Reproduced as documented.

### 4.5 Universal clipboard[^6^][^7^]

| Hotkey | Function |
| --- | --- |
| `Super + C` | Copy |
| `Super + X` | Cut (not in terminal) |
| `Super + V` | Paste |
| `Super + Ctrl + V` | Clipboard manager / history |

Exceptions: the file manager (**Nautilus**) and AI agent CLIs (OpenCode, Claude Code) still need `Ctrl + C/X/V`.[^7^] Clipboard history is provided by **Walker**, works for text and images, searchable by typing.[^7^]

### 4.6 Capture[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + C` | Capture menu (for keyboards w/o PrintScr button) |
| `Print Screen` | Screenshot |
| `Alt + Print Screen` | Screenrecord |
| `Super + Print Screen` | Color picker |
| `Super + Ctrl + Print Screen` | Text extraction to clipboard |
| `Alt + Shift + L` | Copy current URL from webapp or Chromium |
| `Super + Ctrl + X` | Start/stop dictation (requires *Install > AI > Dictation*) |
| `F9` | Push-to-talk dictation (requires *Install > AI > Dictation*) |

Screenrecord: hit hotkey to start, again to stop. All capture options also under *Capture* in the Omarchy menu.[^6^] Text extraction uses the **tesseract** OCR model, result to clipboard.[^10^] Dictation is via **Voxtype** (150 MB base English model; `voxtype setup model`; config `~/.config/voxtype/config.toml`).[^10^] Web Apps page gives the URL-copy binding as `Shift + Alt + L` (same combo, reversed modifier order).[^21^]

### 4.7 Notifications[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + ,` | Dismiss latest notification |
| `Super + Shift + ,` | Dismiss all notifications |
| `Super + Ctrl + ,` | Toggle silencing notifications |
| `Super + Alt + ,` | Invoke most recent notification |

### 4.8 Style[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + Shift + Space` | Pick a new theme |
| `Super + Ctrl + Space` | Pick theme background |
| `Super + Backspace` | Toggle transparency on a window |
| `Super + Ctrl + Backspace` | Toggle single-window square aspect |

Extra backgrounds live in `~/.config/omarchy/current/backgrounds`; also via *Install > Background* in the Omarchy menu. All style options also under *Style* in the Omarchy menu.[^6^]

### 4.9 Toggles[^6^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + I` | Toggle idle/sleep prevention |
| `Super + Ctrl + N` | Toggle nightlight display temperature |
| `Super + Ctrl + Delete` | Toggle laptop display on/off |
| `Super + Ctrl + Alt + Delete` | Toggle laptop display mirroring |
| `Super + Shift + Space` | Toggle the top bar |
| `Super + Mute` | Switch to next audio output |
| `Super + Shift + Backspace` | Toggle window gaps |

### 4.10 Reminders[^6^][^8^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + R` | Set a reminder |
| `Super + Ctrl + Alt + R` | See all reminders |
| `Super + Ctrl + Shift + R` | Clear all reminders |

Also *Trigger > Reminder* menu and CLI: `omarchy reminder 7 'Tea ready'`.[^8^]

### 4.11 Notices[^6^][^9^]

| Hotkey | Function |
| --- | --- |
| `Super + Ctrl + Alt + T` | Show time as notification |
| `Super + Ctrl + Alt + B` | Show battery as notification |
| `Super + Ctrl + Alt + W` | Show weather as notification |

(The Notices page renders the first as "`Super + Ctrl + At + T`" — a typo in the source; hotkeys table used above.[^9^])

### 4.12 Tmux[^6^]

Prefix key is `Ctrl + Space` (`Ctrl + B` also works). Bindings in `~/.config/tmux/tmux.conf`.

**Panes**

| Hotkey | Function |
| --- | --- |
| `Prefix + v` | Split pane beside (vertical) |
| `Prefix + h` | Split pane below (horizontal) |
| `Prefix + x` | Kill pane |
| `Prefix + z` | Toggle pane zoom (fullscreen) |
| `Ctrl + Alt + Arrows` | Move between panes |
| `Ctrl + Alt + Shift + Arrows` | Resize panes |

**Windows**

| Hotkey | Function |
| --- | --- |
| `Prefix + c` | New window |
| `Prefix + k` | Kill window |
| `Prefix + r` | Rename window |
| `Alt + 1-9` | Go to specific window |
| `Alt + Arrow Left/Right` | Move between windows |

**Sessions**

| Hotkey | Function |
| --- | --- |
| `Prefix + C` | New session |
| `Prefix + K` | Kill session |
| `Prefix + R` | Rename session |
| `Prefix + N` | Next session |
| `Prefix + P` | Previous session |
| `Alt + Arrow Up/Down` | Move between sessions |
| `Prefix + s` | List sessions |
| `Prefix + d` | Detach from session |

**Copy mode (vi-style)**: `Prefix + [` enter; `v` begin selection; `y` copy.
**General**: `Prefix + q` reload config; `Prefix + :` command prompt.

**Tmux layout functions** (run inside a Tmux session):[^6^][^12^]

| Command | Function |
| --- | --- |
| `tdl <ai> [<second_ai>]` | Create dev layout with editor, AI, and terminal |
| `tdlm <ai> [<second_ai>]` | Create dev layout per subdirectory |
| `tsl <count> <command>` | Create multi-pane swarm layout |

Detail from Terminal page: `tdl [agent]` = three-way IDE split (`$EDITOR` left, AI agent right — `c` = opencode, `cx` = Claude, `codex` = OpenAI — terminal bottom); shortcuts `ic` / `icx`; `tdlm` repeats per subdirectory navigable via `alt + 1/2/3/5/6/...`; `tsl 4 c` = four-way grid of opencode agents.[^12^]

### 4.13 Ghostty terminal (optional, via *Install > Terminal*)[^6^]

| Hotkey | Function |
| --- | --- |
| `Ctrl + Shift + E` | New split below |
| `Ctrl + Shift + O` | New split besides |
| `Ctrl + Alt + Arrows` | Move between splits |
| `Super + Ctrl + Shift + Arrows` | Resize split by 10 lines |
| `Super + Ctrl + Shift + Alt + Arrows` | Resize split by 100 lines |
| `Ctrl + Shift + T` | New tab |
| `Ctrl + Shift + Arrows` | Move between tabs tab |
| `Alt + Numbers` | Go to specific tab |
| `Shift + Pg Up/Down` | Scroll the history |
| `Ctrl + Left mouse` | Open link in browser |

### 4.14 File Manager (Nautilus)[^6^]

| Hotkey | Function |
| --- | --- |
| `Ctrl + L` | Go to path |
| `Space` | Preview file (arrows navigate) |
| `Backspace` | Go back one folder |

### 4.15 Neovim (w/ LazyVim)[^6^][^13^]

| Hotkey | Function |
| --- | --- |
| `Space` | Show command options (leader) |
| `Space Space` | Open file via fuzzy search |
| `Space E` | Toggle sidebar |
| `Space G G` | Show git controls (LazyGit) |
| `Space S G` | Search file content |
| `Ctrl + W W` | Jump between sidebar and editor |
| `Ctrl + Left/right arrow` | Change size of sidebar |
| `Shift + H` | Go to left file tab |
| `Shift + L` | Go to right file tab |
| `Space B D` | Close file tab |

Sidebar: `A` add file, `Shift + A` add subdir, `D` delete, `M` move, `R` rename, `?` help.[^6^]
Additional from Neovim page: `Space B O` close other tabs; `Space U W` toggle soft wrap; file tree `a` new file / `A` new dir; full keymaps at lazyvim.org/keymaps.[^13^] Start Neovim via `Super + Shift + N` or the `n` alias (alias for `nvim`, opens cwd); `sudoedit` for superuser edits.[^13^]

### 4.16 Quick Emojis (CapsLock = XCompose key)[^6^]

`Super + Ctrl + E` opens a full emoji picker (selection to clipboard). Quick-access sequences:

| Hotkey | EM | Clue |
| --- | --- | --- |
| `CapsLock M S` | 😄 | smile |
| `CapsLock M C` | 😂 | cry |
| `CapsLock M L` | 😍 | love |
| `CapsLock M V` | ✌️ | victory |
| `CapsLock M H` | ❤️ | heart |
| `CapsLock M Y` | 👍 | yes |
| `CapsLock M N` | 👎 | no |
| `CapsLock M F` | 🖕 | fuck |
| `CapsLock M W` | 🤞 | wish |
| `CapsLock M R` | 🤘 | rock |
| `CapsLock M K` | 😘 | kiss |
| `CapsLock M E` | 🙄 | eyeroll |
| `CapsLock M P` | 🙏 | pray |
| `CapsLock M D` | 🤤 | drool |
| `CapsLock M M` | 💰 | money |
| `CapsLock M X` | 🎉 | xellebrate |
| `CapsLock M 1` | 💯 | 100% |
| `CapsLock M T` | 🥂 | toast |
| `CapsLock M O` | 👌 | ok |
| `CapsLock M G` | 👋 | greeting |
| `CapsLock M A` | 💪 | arm |
| `CapsLock M B` | 🤯 | blowing |

### 4.17 Quick Completions[^6^]

| Hotkey | Completion |
| --- | --- |
| `CapsLock Space Space` | — (mdash) |
| `CapsLock Space N` | Your name (as entered on setup) |
| `CapsLock Space E` | Your email (as entered on setup) |

Extend via `~/.XCompose`, then run `omarchy-restart-xcompose`.[^6^] Caps Lock is designated the XCompose key; remap via `kb_options = compose:ralt` in `~/.config/hypr/input.conf` if missed.[^41^]

---

## 5. Theming system

### 5.1 How themes work[^5^]
- "Omarchy comes with **nineteen** beautiful themes."
- Switch via *Style > Theme* in the Omarchy Menu (`Super + Alt + Space`) or the direct theme selector `Super + Ctrl + Shift + Space`.
- "Each theme styles the **desktop, terminal, neovim, activity screen (btop), notifications (mako), top bar (waybar), application launcher (walker), and the lock screen (hyprlock)**." Obsidian requires manually selecting the Omarchy theme inside the app (*Appearance > Themes*).[^5^]
- Theme generation detail (Making-your-own-theme page): the main file is **`colors.toml`**, which "defines the color set that's then used to generate configurations for the terminal (**Ghostty/Alacritty/Kitty**), **btop, Chromium, Hyprland, Hyprlock, Mako, SwayOSD, Walker, and Waybar**."[^38^]
- Each theme ships a set of background images; cycle with `Super + Ctrl + Space`.[^5^]
- Themes may also have a custom **unlock design** (boot decryption screen), selectable under *Style > Unlock*.[^5^]

### 5.2 The 19 bundled themes (verbatim order)[^5^]

1. Tokyo Night
2. Catppuccin
3. Lumon
4. Ethereal
5. Everforest
6. Gruvbox
7. Miasma
8. Hackerman
9. Osaka Jade
10. Kanagawa
11. Nord
12. Matte Black
13. Vantablack
14. Ristretto
15. Retro 82
16. Flexoki Light
17. Rose Pine
18. Catppuccin Latte
19. White

### 5.3 Bundled unlock designs (verbatim list, 19)[^5^]
Catppuccin, Catppuccin Latte, Ethereal, Everforest, Flexoki Light, Gruvbox, Hackerman, Kanagawa, Lumon, Matte Black, Miasma, Nord, Osaka Jade, Retro 82, Ristretto, Rose Pine, Tokyo Night, Vantablack, White.

### 5.4 Custom themes[^38^]
- User themes go in `~/.config/omarchy/themes`; copy a base from `~/.local/share/omarchy/themes`. Anything in that folder appears in the theme selection menu.
- **Light mode:** drop an empty `light.mode` file in the theme root → auto-paired with light mode for all apps.
- **Icon colors:** add `icons.theme` containing an icon-set name. Default options verbatim: `Yaru Yaru-blue Yaru-dark Yaru-magenta Yaru-olive Yaru-prussiangreen Yaru-purple Yaru-red Yaru-sage Yaru-wartybrown Yaru-yellow`.
- **Unlock image:** ship `unlock.png` (preferably transparent) + `preview-unlock.png`; preview via `omarchy plymouth preview`. Listed under *Style > Unlock*.
- **Aether:** an included GUI app for creating themes ("play with colors and search for backgrounds"), started from the app launcher.[^38^]
- **Distribution:** put the theme on a public git server; install via *Install > Theme* with the URL; naming convention `omarchy-[themename]-theme` so it displays as `[themename]`. Get listed on the extra-themes page by pinging @tahayvr on Discord.[^38^]

### 5.5 Extra/community themes[^37^]
Installed by copying the GitHub URL into *Install > Style > Theme*; removed via *Remove > Style > Theme*. Full list as published (104 entries, alphabetical, verbatim names; GitHub URLs on the page):

Aetheria, Amberbyte, Arc Blueberry, Archwave, Ash, Artzen, Aura, All Hallow's Eve, Atelier, Ayaka, Azure Glow, Batman, Batou, Bauhaus, Biscuit de Mar Dark, Black Arch, Black Gold, Black Turq, bluedotrb, Blue Ridge Dark, Catppuccin Mocha Dark, Citrus Cynapse, City-783, Cobalt2, CpUnk, Darcula, Demon, Dotrb, Dos Moos, Drac, Dracula, Eldritch, Event Horizon, Evergarden, Felix, Fireside, Flat Dracula, Flexoki Dark, Forest Green, Frost, Futurism, Ghost Pastel, Gold Rush, Golden Brown, The Greek, Greek Noir, Green Garden, Gruvu, Harbor, Harbor Dark, Hinterlands, Infernium, Inky Pinky, Last Horizon, Map Quest, Mars, Mechanoonna, Miasma, Midnight, Milky Matcha, Monochrome, Monokai, Moodpeak, Nagai Poolside, Neo Sploosh, Neovoid, NES, Omacarchy, One Dark Pro, Oxo Carbon, Pandora, Pina, Pink Blood, Pulsar, Purple Moon, Purplewave, Rainy Night, Red Monarch, Retro 82, RetroPC, Ristretto Light, RobZee84, Rose Pine Dark, Rose of Dune, Ryu, Sakura, Sakura Mochi, Saga, Sapphire, Shades of Jade, Space Monkey, Snow, Snow Black, Solarized, Solarized Light, Solarized Osaka, Solitude, Sunset, Sunset Drive, Super Game Bro, Synthwave '84, Temerald, Tokyo Night OLED, Tycho, Waffle Cat, Waveform Dark, White Gold, Windows Dark Mode, Van Gogh, Velvet Night, Venice from Above, Vesper, VHS 80, Void.

### 5.6 Backgrounds[^33^]
- Live in `~/.config/omarchy/backgrounds/[theme]`; drop a file into e.g. `~/.config/omarchy/backgrounds/nord` to add one (then pick with `Super + Ctrl + Space`).
- Easiest path: *Install > Style > Background* in the Omarchy Menu opens the folder.
- Curated external collection: https://github.com/dharmx/walls.
- (Hotkeys page also references `~/.config/omarchy/current/backgrounds` for the active theme's set.[^6^])

---

## 6. Default applications & component stack

| Role | Default | Evidence |
| --- | --- | --- |
| Window manager / compositor | Hyprland (dwindle layout) | [^2^][^4^] |
| Terminal | **Alacritty** (no native tabs/splits/image rendering; Ghostty, Foot, Kitty supported via *Install > Terminal*) | [^12^] |
| Browser | **Chromium** (ships; themed; frameless web-app windows run on it) | [^2^][^38^][^21^] |
| Editor | **Neovim** with LazyVim distribution | [^13^] |
| File manager | **Nautilus** (`Super + Shift + F`) | [^7^][^6^] |
| App launcher | **Walker** (`Super + Space`; also provides clipboard history) | [^5^][^7^][^27^] |
| Notifications | **mako** | [^5^] |
| Top bar | **Waybar** | [^5^][^27^] |
| Lock screen | **hyprlock** (themed via symlink) | [^5^][^27^] |
| OSD | **SwayOSD** (themed) | [^38^] |
| Idle daemon | hypridle (`~/.config/hypr/hypridle.conf`) | [^27^] |
| Shell prompt | **Starship** (minimal config, `~/.config/starship.toml`) | [^34^] |
| Shell | bash — user aliases/functions go in `~/.bashrc` ("will not be overwritten on updates") | [^27^] |
| Terminal multiplexer | **tmux**, prefix `Ctrl + Space`, `Super + Alt + Return` launches tmux terminal | [^6^][^12^] |
| Bootloader | **Limine** (default since Omarchy 2.0) | [^43^][^39^] |
| Boot splash / decrypt UI | Plymouth (`omarchy plymouth preview/set/reset`), per-theme unlock designs | [^35^][^38^] |
| System font | **JetBrainsMono Nerd Font** (terminal + system); change via *Style > Font*; more via *Install > Style > Font* | [^32^] |
| PDF viewer | "Document Viewer" (form PDFs); **Xournal++** for non-form fill/sign | [^23^] |
| Media player | mpv | [^19^] |
| Password manager | 1Password (`Super + Shift + /`) | [^20^] |
| Mail/calendar | HEY web apps | [^21^] |
| Notes | Obsidian (`Super + Shift + O`) | [^19^] |
| AI agent CLIs | **OpenCode** (`c` alias) and **Claude Code** (`cx` alias, "danger mode") | [^14^] |
| Session/desktop launcher | **uwsm** (`~/.config/uwsm/default` controls default `$EDITOR`) | [^27^] |
| Emoji/compose | XCompose on CapsLock; emoji picker on `Super + Ctrl + E` | [^6^] |
| Snapshot system | btrfs snapshots via Limine (`omarchy-snapshot create/restore`) | [^43^] |
| Firewall | ufw (+ ufw-docker), default deny incoming except 22 (ssh) and 53317 (LocalSend) | [^44^] |

The default editor is changeable under `Setup > Defaults > Editor`; alternative editors offered under *Install > Editor*: VSCode, Cursor, Zed, Sublime Text, Helix (theme matching for VSCode, Cursor, VSCodium, Helix, Zed).[^15^]

---

## 7. TUIs (verbatim summaries)[^18^]

- **Lazygit** — terminal git UI ("delightful alternative to something like the GitHub Desktop application"); run `lazygit` in a repo or `Space G G` inside Neovim; `Tab` hops panes, `Space` stages, `c` commits, `?` help.
- **Lazydocker** — container/image management TUI; `Super + Shift + D`; `s` stop, `r` start/restart, `?` help.
- **Btop** — resource manager (memory/CPU/disk/network + process management); packaged in Omarchy as the "Activity" app. ⚠ TUIs page says launch with `Super + Shift + T`[^18^] while the Hotkeys table says `Super + Ctrl + T` for "Activity (btop)"[^6^] — documented discrepancy.
- **Impala** — Wi-Fi management TUI (`Super + Ctrl + W` per hotkeys[^6^]); also via the Wi-Fi icon in the top bar; tab between sections, space to select network.
- **BlueTUI** — Bluetooth TUI, same creator/style as Impala (`Super + Ctrl + B`).[^18^][^6^]
- **Fastfetch** — system info (kernel, uptime, theme, CPU, memory); successor to neofetch; packaged as *About* in the Omarchy menu.[^18^]
- **Cliamp** — retro Winamp-2.x-inspired terminal music player with built-in lo-fi radio; `Super + Shift + Alt + M` or Omarchy menu *Apps*; `?` for keys.[^18^]
- **wiremix** — audio controls TUI (`Super + Ctrl + A`, named in hotkey table only).[^6^]
- **Omarchy Menu** itself is the central TUI (`Super + Alt + Space`), and the **`omarchy` CLI** exposes the same internal tooling for scripting/AI agents (`omarchy update`, `omarchy theme list/set`, `omarchy font list`, `omarchy screenshot`, `omarchy debug`; groups: ac, battery, branch, brightness, capture, channel, cmd, config, debug, dev, drive, font, ...).[^11^]
- Also: **Hyprmon** (TUI for monitor positioning, third-party, recommended).[^28^] **Aether** (GUI theme creator).[^38^]

---

## 8. Design language

- **Corners:** square by default — "Omarchy's default design is one of square corners"; rounding opt-in via `~/.config/hypr/looknfeel.conf` → `decoration { rounding = 8 }`.[^36^]
- **Gaps/borders:** gaps exist by default; removable via `looknfeel.conf` → `general { gaps_in = 0; gaps_out = 0; border_size = 0 }`; runtime toggle `Super + Shift + Backspace`.[^36^][^6^] Exact default gap/border pixel values: **not found in manual**.
- **Top bar (Waybar):** single top bar; toggle with `Super + Shift + Space`[^6^]; clock format default `"{:%A %H:%M}"` (24h)[^42^]; tray icons hidden behind a "tray expander" by default (`group/tray-expander` → `tray` to expose)[^36^]; speaker icon top-right launches volume controls ("d" sets default output)[^41^]; Wi-Fi icon opens Impala[^18^]; update-available indicator is "a circle arrow icon ... to the right of your clock"[^26^]. Layout config `~/.config/waybar/config.jsonc`, style `~/.config/waybar/style.css` (symlinked to theme).[^27^]
- **Fonts:** JetBrainsMono Nerd Font everywhere by default; 2x "retina-class" rendering assumed.[^32^][^28^]
- **Display assumption:** 2x scaling on 218+ PPI displays; fractional scaling examples for 4K (`GDK_SCALE,1.75` + `monitor=,preferred,auto,1.666667`); `Super + /` cycles 1x/1.6x/2x/3x.[^28^]
- **Prompt:** minimal Starship — "I don't need to know the user, because it's always me, and I don't need to know the time, because it's always at the top."[^34^]
- **Colors:** theme-driven everywhere via generated configs from `colors.toml` (10 target apps incl. SwayOSD and Chromium).[^38^]
- **Wallpapers:** per-theme background sets, curated, switchable; external curation repo linked.[^5^][^33^]
- **Branding/customization:** boot unlock (Plymouth) logo via `omarchy plymouth set`; ASCII-logo screensaver under *Style > Screensaver* (png/svg auto-converted to ASCII); *About* screen logo under *Style > About*.[^35^]
- **Transparency:** `Super + Backspace` toggles per-window transparency; `Super + Ctrl + Backspace` toggles single-window square aspect.[^6^]
- **Web apps** run in "the beautiful frameless web-app window".[^21^]
- **Night light:** `Super + Ctrl + N` toggles nightlight color temperature.[^6^]

---

## 9. Omarchy Menu map (TUI) — all documented menu paths

The Omarchy Menu (`Super + Alt + Space`) is the control hub. Every menu path referenced across the manual:

- *Style > Theme*[^5^], *Style > Unlock*[^5^][^38^], *Style > Font*[^32^], *Style > Screensaver*[^35^], *Style > About*[^35^]
- *Install > Theme*[^38^], *Install > Style > Theme* / *Remove > Style > Theme*[^37^], *Install > Style > Background*[^33^], *Install > Style > Font*[^32^], *Install > Background*[^6^]
- *Install > Terminal* (Alacritty/Ghostty/Foot/Kitty)[^12^][^6^]
- *Install > Editor* (VSCode, Cursor, Zed, Sublime Text, Helix)[^15^]
- *Install > Package*, *Install > AUR*, *Remove > Package*[^25^][^42^]
- *Install > Development* (Rails, Node.js, bun, Deno, Laravel, Symfony, .NET, OCaml, Zig, Elixir); *Install > Development > Docker DB*[^15^]
- *Install > Service > Dropbox / Tailscale / NordVPN*[^20^]
- *Install > Web App*, *Remove > Web App*[^21^][^42^]
- *Install > AI* (LM Studio, Ollama); *Install > AI > Dictation* (Voxtype)[^14^][^10^][^6^]
- *Install > Gaming* (Steam, RetroArch, Xbox Cloud Gaming, NVIDIA GeForce Now, Minecraft, Moonlight, Lutris, Heroic; *Install > Gaming > Remove*); *Install > Xbox Controllers*[^22^]
- *Install > Windows* (Docker-based Windows 11 Pro VM via RDP; `~/Windows` shared; config `~/.config/windows/docker-compose.yml`)[^24^]
- *Setup > Defaults* (incl. *Setup > Defaults > Editor*; env vars `OMARCHY_SCREENSHOT_DIR`, `OMARCHY_SCREENRECORD_DIR`)[^15^][^42^]
- *Setup > Configs > [process]* (edits config in Neovim, auto-restarts processes on `:wq`)[^27^]; *Setup > Config > Waybar*[^36^]
- *Setup > Monitors*[^28^], *Setup > Input*[^29^], *Setup > Security > Fingerprint* / *Setup > Security > Fido2* (removal under *Remove > Fingerprint* / *Remove > Fido2*)[^31^]
- *Setup > System Sleep > Enable/Disable Suspend / Hibernation* (hibernation creates /swap subvolume sized to RAM)[^30^]
- *Update > Omarchy* (pulls latest code + migrations + packages from Omarchy Arch Mirror, Omarchy Package Repository, AUR); *Update > Channel* (stable/RC/edge/dev); *Update > Config* (restore config defaults)[^26^][^36^][^27^]
- *Trigger > Share* (LocalSend)[^19^], *Trigger > Hardware* (display mirroring/lid)[^28^], *Trigger > Reminder*[^8^]
- *Capture* menu (screenshot/record/picker/OCR)[^6^]
- *About* (Fastfetch)[^18^]
- System menu (suspend/restart/etc.) on `Super + Escape`[^6^][^30^]

### `omarchy` CLI[^11^]
Mirrors menu/internal tooling; `omarchy commands [--all] [--json] [--check]`; common: `omarchy update`, `omarchy theme list/set <name>`, `omarchy font list`, `omarchy screenshot`, `omarchy debug`. Groups shown: ac, battery, branch, brightness, capture, channel, cmd, config, debug, dev, drive, font (list truncated in source with "…"-style cut-off — full group list **not fully shown in manual**). Example subcommands: `omarchy capture screenrecording [--with-desktop-audio] [--with-microphone-audio] [--with-webcam] [--webcam-device=<device>] [--resolution=<size>] [--stop-recording]`; `omarchy capture screenshot [smart|region|windows|fullscreen] [slurp|copy] [--editor=<name>]`; `omarchy capture text extraction`.[^11^] Other CLI commands referenced elsewhere: `omarchy pkg add/drop`[^25^], `omarchy reminder`[^8^], `omarchy plymouth preview/set/reset`[^35^][^38^], `omarchy reinstall` / `omarchy reinstall configs`[^26^][^27^], `omarchy-snapshot create/restore`[^43^], `omarchy-debug`[^41^], `omarchy-reinstall`[^41^][^36^], `omarchy-restart-xcompose`[^6^][^27^], `omarchy-npx-install <package> [command-name]`[^14^].

---

## 10. Configuration model (dotfiles)[^27^]

- User-owned: `~/.config`; Omarchy-owned: `~/.local/share/omarchy` (don't edit; override in `~/.config`).
- Key files (verbatim table):[^27^]

| File | Purpose |
| --- | --- |
| `~/.config/hypr/hyprland.conf` | Controls keybindings, default apps, and everything Hyprland |
| `~/.config/hypr/monitors.conf` | Controls your monitors, resolution, and position |
| `~/.config/hypr/hypridle.conf` | Controls your idle/sleep settings |
| `~/.config/hypr/hyprlock.conf` | Lock screen (symlinked to theme for styling) |
| `~/.config/waybar/config.jsonc` | Top bar config |
| `~/.config/waybar/style.css` | Top bar design (symlinked to theme) |
| `~/.config/walker/config.toml` | Launcher config |
| `~/.config/alacritty/alacritty.toml` | Terminal config |
| `~/.config/uwsm/default` | Default $EDITOR (requires Hyprland relaunch) |
| `~/.XCompose` | Emoji + name/email autocomplete |

- Other config files referenced: `~/.config/hypr/bindings.conf` (hotkeys)[^6^], `~/.config/hypr/looknfeel.conf` (layout/rounding/gaps)[^4^][^36^], `~/.config/hypr/input.conf` (keyboard layouts, repeat, touchpad, swap_alt_win)[^29^][^41^], `~/.config/tmux/tmux.conf`[^6^], `~/.config/starship.toml`[^34^], `~/.config/voxtype/config.toml`[^10^], `~/.config/windows/docker-compose.yml`[^24^], `~/.bashrc` (user aliases/exports, update-safe)[^27^].
- Internal-file edits must be committed (`gcam "..."` inside `~/.local/share/omarchy`) before `omarchy update` will run.[^27^]
- Reset: *Update > Config* or `omarchy reinstall configs`.[^27^]
- Updates may restore configs, keeping user changes in `.bak` files.[^36^]
- Example rebind given: `bind = SUPER SHIFT, O, exec, joplin`.[^27^]
- Input example (verbatim) includes `repeat_rate = 40`, `repeat_delay = 600`, `sensitivity = 0.35`, `natural_scroll = true`, `clickfinger_behavior = true`, `scroll_factor = 0.3`, and `windowrule = scrolltouchpad 1.5, tag:terminal`; ALT-as-SUPER via `kb_options = compose:caps,altwin:swap_alt_win`.[^29^]

---

## 11. Shell tools, functions, dev environment

**Shell tools** (verbatim summaries):[^16^]
- **fzf** — fuzzy file finding via `ff` alias with preview; `Ctrl + R` history search; backs Neovim `Space Space`.
- **zoxide** — cd replacement with directory memory (`cd oma` → `~/.local/share/omarchy`).
- **ripgrep** — `rg <pattern> <path>`; backs Neovim `Space S G`.
- **eza** — ls replacement (aliased as `ls`); `lt` two-level tree, `lsa` incl. hidden, `lta` nested + hidden.
- **fd** — find replacement (`fd person.rb / -H`).
- **try** — date-stamped experiment dirs in `~/Work/tries`.

**Shell functions:**[^17^] `compress`/`decompress` (tar.gz), `iso2sd` (bootable SD), `format-drive` (exFAT), SSH port-forward trio `fip`/`dip`/`lip` (forward/disconnect/list; e.g. `fip nyc-dev 3000`).

**Dev tools:**[^15^] Mise manages most language envs (`mise use -g ruby`, `mise i`); Docker + Compose + user-group setup preinstalled; `gh` CLI + lazy-installing `ghui` stub for PRs; databases via *Install > Development > Docker DB*.

**AI:**[^14^] OpenCode (`c`) + Claude Code (`cx`) default; lazy npx stubs `codex`, `gemini`, `copilot`, `pi` (npm packages fetched on first run via mise-managed node@latest); local LLMs via LM Studio (GUI) or Ollama (CLI) under *Install > AI*; an experimental "Omarchy Skill" for AI harnesses (`~/.claude/skills`-compatible) that can edit waybar/themes — "best to run in plan mode first."

**GUIs:**[^19^] Obsidian, Pinta, LocalSend, LibreOffice, Signal, mpv, OBS Studio, Kdenlive.
**Commercial:**[^20^] 1Password, Typora ($15 one-time after 15-day trial), Spotify, Dropbox, Tailscale, NordVPN.
**Web apps (preinstalled):**[^21^] HEY (email `Super + Shift + E`, calendar `Super + Shift + C`), Basecamp, ChatGPT (`Super + Shift + A`), WhatsApp, X, YouTube (`Super + Shift + Y`), Zoom; custom web apps via *Install > Web App* (name/URL/icon; Dashboard Icons recommended); all web-app hotkeys in `~/.config/hypr/bindings.conf`.
**Gaming:**[^22^] Steam, RetroArch (CRT Royale shader preconfigured; ROMs in `~/Games`), Xbox Cloud Gaming, GeForce NOW, Minecraft, Moonlight (+Sunshine), Lutris (Battle.net), Heroic (Epic, no anti-cheat titles).
**Other packages:**[^25^] *Install > Package* / *Install > AUR* fuzzy installers (`omarchy pkg add/drop`).

---

## 12. Updates, snapshots, security

- Update via *Update > Omarchy*: pulls latest code/configs, runs migrations, updates packages from the Omarchy Arch Mirror + Omarchy Package Repository + AUR. Update indicator: circle-arrow icon right of the clock.[^26^]
- **Channels:** stable (default; mirror one month behind), edge (latest Arch packages), RC (pre-release validation), dev (latest code + edge packages). Switch via *Update > Channel*.[^26^]
- **Snapshots:** automatic before every update; manual `omarchy-snapshot create`; restore by booting the snapshot from Limine (version shown bottom-left), then click the notification or run `omarchy-snapshot restore`. Restores `/root` but **not** `/home` or `~/.config`. Limine-only (default since Omarchy 2.0); not on GRUB/systemd-boot.[^43^]
- **Reinstall:** `omarchy reinstall` restores latest release, stable channel, downgrades packages, resets configs (user config changes lost).[^26^]
- **Security model (verbatim five points):**[^44^] (1) full-disk encryption mandatory (LUKS); (2) firewall on by default — only ports 22 and 53317 open, ufw-docker locks containers; (3) Arch rolling = latest security patches; (4) Omarchy uses only Arch core/extra/multilib + its own repo by default (AUR opt-in only); (5) all distribution infrastructure behind Cloudflare DDoS protection/CDN.
- Signing key: `40DFB630FF42BCFFB047046CF0134EE680CAC571` (pkgs@omarchy.org; in `omarchy/omarchy-keyring`); ISO signatures at `https://iso.omarchy.org/omarchy-x.x.x.iso.sig`.[^44^]
- Hardware auth: fingerprint via *Setup > Security > Fingerprint* (lock screen, sudo, system prompts; `Ctrl+C` to skip at sudo prompt); Fido2 for sudo only.[^31^]
- Auto-login after disk decryption (by design).[^39^] Failed-login lockout reset: TTY (`Ctrl+Alt+F2`) → `faillock --reset --user <name>`.[^41^]

---

## 13. "Omarchy on..." — ports & alternative platforms[^45^]

- Apple M1/M2: Asahi Alarm + community guide (codeberg omarchy-mac).
- Parallels VM, VirtualBox, VMware Workstation on Windows 11: community guides (GitHub discussions).
- Steam Deck: "deckarchy" setup script.
- **NixOS**: "Omarchy is really Arch + Hyprland, but Henry Sipp has ported the essence of the setup to NixOS" — https://github.com/henrysipp/omarchy-nix — "a good starting point. It may or may not stay up-to-date with the latest Omarchy changes."[^45^] (Directly relevant to the kebun project.)
- Community channel: `#omarchy-on-other` on Discord.

---

## 14. Documented discrepancies & "not found in manual"

**Internal discrepancies (verbatim, un-resolved):**
1. btop/Activity launcher: `Super + Shift + T` (TUIs page[^18^]) vs `Super + Ctrl + T` (Hotkeys[^6^]).
2. WhatsApp: `Super + Ctrl + G` (Web Apps[^21^]) vs `Super + Shift + Alt + G` (Hotkeys[^6^]).
3. "Shift + Brightness Up" listed for both max AND min brightness (Adjustments table[^6^]).
4. Notices page prints "`Super + Ctrl + At + T`" for time (typo)[^9^].
5. URL-copy binding written `Alt + Shift + L` (Hotkeys[^6^]) and `Shift + Alt + L` (Web Apps[^21^]).

**Not found in manual (flagged):**
- Exact Omarchy point-release version number (only "Omarchy 3" era references).
- Default gap/border pixel values, border width/color specifics (only that square corners are default and gaps exist).
- Full Waybar module layout (only clock format, tray expander, speaker/wifi icons, update indicator are described).
- Color palettes/hex values for any bundled theme (themes are presented as screenshots; `colors.toml` is named but no values given).
- The complete list of `omarchy` CLI groups (source output is truncated).
- Which exact workspaces exist by default (bindings only show 1–4).
- Default keyrepeat values, touchpad defaults (only example configs given).
- The name/content of the default bundled background images.
- The Omarchy Menu's full item tree (only paths referenced in prose; no dedicated menu page exists).

---

## Footnotes (sources)

[^1^]: https://learn.omacom.io/2/the-omarchy-manual
[^2^]: https://learn.omacom.io/2/the-omarchy-manual/91/welcome-to-omarchy
[^3^]: https://learn.omacom.io/2/the-omarchy-manual/50/getting-started
[^4^]: https://learn.omacom.io/2/the-omarchy-manual/51/navigation
[^5^]: https://learn.omacom.io/2/the-omarchy-manual/52/themes
[^6^]: https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys
[^7^]: https://learn.omacom.io/2/the-omarchy-manual/105/universal-clipboard-history
[^8^]: https://learn.omacom.io/2/the-omarchy-manual/117/reminders
[^9^]: https://learn.omacom.io/2/the-omarchy-manual/119/notices
[^10^]: https://learn.omacom.io/2/the-omarchy-manual/116/text-extraction-dictation
[^11^]: https://learn.omacom.io/2/the-omarchy-manual/115/omarchy-cli
[^12^]: https://learn.omacom.io/2/the-omarchy-manual/106/terminal
[^13^]: https://learn.omacom.io/2/the-omarchy-manual/56/neovim
[^14^]: https://learn.omacom.io/2/the-omarchy-manual/107/ai
[^15^]: https://learn.omacom.io/2/the-omarchy-manual/62/development-tools
[^16^]: https://learn.omacom.io/2/the-omarchy-manual/57/shell-tools
[^17^]: https://learn.omacom.io/2/the-omarchy-manual/58/shell-functions
[^18^]: https://learn.omacom.io/2/the-omarchy-manual/59/tuis
[^19^]: https://learn.omacom.io/2/the-omarchy-manual/60/guis
[^20^]: https://learn.omacom.io/2/the-omarchy-manual/61/commercial
[^21^]: https://learn.omacom.io/2/the-omarchy-manual/63/web-apps
[^22^]: https://learn.omacom.io/2/the-omarchy-manual/71/gaming
[^23^]: https://learn.omacom.io/2/the-omarchy-manual/54/filling-out-pdfs
[^24^]: https://learn.omacom.io/2/the-omarchy-manual/100/windows-vm
[^25^]: https://learn.omacom.io/2/the-omarchy-manual/66/other-packages
[^26^]: https://learn.omacom.io/2/the-omarchy-manual/68/updates
[^27^]: https://learn.omacom.io/2/the-omarchy-manual/65/dotfiles
[^28^]: https://learn.omacom.io/2/the-omarchy-manual/86/monitors
[^29^]: https://learn.omacom.io/2/the-omarchy-manual/78/keyboard-mouse-trackpad
[^30^]: https://learn.omacom.io/2/the-omarchy-manual/103/system-sleep
[^31^]: https://learn.omacom.io/2/the-omarchy-manual/77/hardware-authentication
[^32^]: https://learn.omacom.io/2/the-omarchy-manual/94/fonts
[^33^]: https://learn.omacom.io/2/the-omarchy-manual/89/backgrounds
[^34^]: https://learn.omacom.io/2/the-omarchy-manual/95/prompt
[^35^]: https://learn.omacom.io/2/the-omarchy-manual/118/branding
[^36^]: https://learn.omacom.io/2/the-omarchy-manual/102/common-tweaks
[^37^]: https://learn.omacom.io/2/the-omarchy-manual/90/extra-themes
[^38^]: https://learn.omacom.io/2/the-omarchy-manual/92/making-your-own-theme
[^39^]: https://learn.omacom.io/2/the-omarchy-manual/96/manual-installation
[^40^]: https://learn.omacom.io/2/the-omarchy-manual/97/mac-support
[^41^]: https://learn.omacom.io/2/the-omarchy-manual/88/troubleshooting
[^42^]: https://learn.omacom.io/2/the-omarchy-manual/67/faq
[^43^]: https://learn.omacom.io/2/the-omarchy-manual/101/system-snapshots
[^44^]: https://learn.omacom.io/2/the-omarchy-manual/93/security
[^45^]: https://learn.omacom.io/2/the-omarchy-manual/79/omarchy-on
