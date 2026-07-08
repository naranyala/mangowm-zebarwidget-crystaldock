# Shell Removal Impact Analysis

> Impact assessment of removing DankMaterialShell, Noctalia, and Crystal Dock from the OCWS dotfiles setup.

---

## Removing DankMaterialShell (DMS)

### Lost Features

| Category | Features Lost |
|----------|--------------|
| **Theming** | matugen dynamic color generation for 20+ apps (GTK, Qt, terminals, editors, browsers) |
| **Lock Screen** | Built-in with fingerprint, U2F, profile image, media player, power actions |
| **Notifications** | Built-in daemon with overlay, popup, shadow, history, per-app rules, urgency timeouts |
| **Control Center** | Unified panel with volume/brightness sliders, WiFi, Bluetooth, audio, night mode, dark mode |
| **Wallpaper** | Built-in manager with fill modes, overlay support |
| **Desktop Widgets** | Clock (analog/digital), system monitor, weather |
| **Privacy** | Mic/camera/screenshare per-app indicators |
| **Notepad** | Built-in with monospace, line numbers, transparency |
| **App Launcher** | List/grid views, spotlight mode, browser/file pickers |
| **Display Management** | Display profiles, snap-to-edge, per-output settings |
| **Firefox CSS** | Material 3 themed Firefox (`firefox.css`) |

### matugen Template Coverage (DMS Exclusive)

DMS generates themes for these applications:
- **GTK**: GTK3, GTK4
- **Qt**: Qt5ct, Qt6ct
- **Compositor**: Niri, Hyprland, Mangowc
- **Terminals**: Ghostty, Kitty, Foot, Alacritty, Wezterm
- **Editors**: Neovim, VSCode, Emacs, Zed
- **Browsers**: Firefox, Zen Browser, Vesktop, Equibop
- **Other**: Pywalfox, Kcolorscheme

---

## Removing Noctalia

### Lost Features

| Category | Features Lost |
|----------|--------------|
| **Theming** | 13 built-in themes, wallpaper-based color extraction, community themes |
| **Lock Screen** | Built-in with blurred desktop, blur/tint intensity |
| **Notifications** | Built-in with filtering, actions, history, per-app rules |
| **Wallpaper** | Transitions (fade/wipe/disc/stripes/zoom/honeycomb), auto-rotate, light/dark dirs |
| **Backdrop** | Blur + tint overlay effect |
| **Night Light** | Built-in (configurable temperature, no external gammastep needed) |
| **Idle Management** | Built-in with pre-action fade overlay, lock/screen-off timeouts |
| **Hooks System** | Event-driven: wallpaper change, theme change, session lock/unlock, WiFi/BT toggle, battery threshold |
| **OSD** | 13 kinds (volume, brightness, WiFi, BT, power profile, caffeine, nightlight, DND, lock keys, keyboard layout, privacy) |
| **Capsule Bar Mode** | Pill-shaped bar with configurable fill, radius, opacity, border |
| **Per-Monitor** | Bar overrides per output, dock per-monitor |
| **System Monitor** | Built-in with CPU, memory, network, disk polling |
| **Weather** | Built-in (Open-Meteo integration) |

### Noctalia Built-in Themes

Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa, Noctalia, Nord, Rosé Pine, Tokyo Night

### Wallpaper Transition Effects

`fade`, `wipe`, `disc`, `stripes`, `zoom`, `honeycomb`

---

## Removing Crystal Dock

### Lost Features

| Category | Features Lost |
|----------|--------------|
| **Dock** | macOS-style Qt dock with smooth animations |
| **Magnification** | Zoom effect on hover (`zoomingAnimationSpeed`) |
| **Bouncing Icons** | Launcher bounce animation |
| **Classic Layout** | Separate panel + dock (sfwbar top, crystal-dock bottom) |
| **Qt Integration** | Native Qt dock (better Qt app integration) |

---

## What OCWS Native (sfwbar) Already Provides

| Feature | Status | Notes |
|---------|--------|-------|
| 65+ widgets |  | CPU, memory, disk, network, battery, etc. |
| Dual-panel layout |  | Top bar + bottom bar |
| Dock widget |  | Basic (no magnification) |
| Clipboard history |  | Via wl-paste/cliphist |
| Media player controls |  | MPRIS integration |
| System tray |  | StatusNotifierItem |
| Workspace switcher |  | wlr-workspaces |
| Calendar popup |  | clock.widget |
| Quick settings |  | quick-settings.widget |
| Control center |  | ocws-control-center.widget |
| Notification center |  | notification-center.widget |
| Weather widget |  | Open-Meteo |
| Desktop widgets |  | Clock, sysmon, weather |

---

## Replacement Requirements

If removing all three shells, these external tools would be needed:

| Function | External Tool | Notes |
|----------|--------------|-------|
| Lock screen | `gtklock`, `swaylock`, `nwg-hello` | No fingerprint/U2F support |
| Notifications | `mako`, `dunst` | No built-in history/rules |
| Wallpaper | `swaybg` | No transitions, no auto-rotate |
| Night light | `gammastep` | Manual config required |
| Idle management | `swayidle` | No pre-action fade overlay |
| Dock magnification | Custom sfwbar widget | Not currently implemented |

---

## Summary: Impact by Category

| Category | DMS | Noctalia | Crystal Dock | OCWS Native |
|----------|-----|----------|--------------|-------------|
| Dynamic theming |  matugen |  wallpaper-based |  |  |
| Lock screen |  full |  basic |  |  |
| Notifications |  daemon |  daemon |  |  widget |
| Wallpaper transitions |  |  6 effects |  |  |
| Night light |  toggle |  built-in |  |  |
| Idle management |  |  built-in |  |  |
| Dock magnification |  |  |  zoom |  |
| Bouncing icons |  |  |  |  |
| Capsule bar mode |  |  |  |  |
| Hooks system |  |  |  |  |
| Control center |  |  |  |  |
| System monitor |  |  |  |  |
| Weather |  |  |  |  |

---

## Recommendation

**Keep OCWS Native (sfwbar) as the primary shell** — it has the most widgets and is self-contained.

**Consider keeping Noctalia** as an alternative for users who want:
- Built-in lock screen, notifications, night light, idle management
- Wallpaper transitions
- TOML-based configuration
- Fewer external dependencies

**DMS and Crystal Dock are optional** for users who specifically want:
- DMS: Material Design aesthetics, matugen dynamic theming
- Crystal Dock: macOS-style dock experience

---

*Generated: 2026-07-07*
*Project: OCWS (Our C-Written Shell)*
