# OCWS (Our C-Written Shell) Strategic Roadmap & TODOs

## Strategic Focus Areas

This document outlines the multi-phase strategy for the development of **OCWS** and the
`labwc-fuzzel-sfwbar` platform. Focus is exclusively on this pure C-native Wayland paradigm.

**Key Priority**: Make OCWS a cohesive, complete "batteries-included" platform.

---

## Phase 1: Platform Consolidation & Core Infrastructure

*Status: COMPLETE*

### Completed Items

- [x] **Widget System Unification**: Merged shell/widgets/ with dotfiles/ocws/ implementations
- [x] **Plugin Autoloader**: `~/.config/ocws/plugins/` auto-injected at boot
- [x] **Event Bus API**: `ocws-emit` with full namespace coverage (System.*, Media.*, Network.*)
- [x] **Theme Engine**: INI profiles -> templates -> rendered configs (11 config surfaces)
- [x] **C Utility Suite**: 15 binaries built via `zig build`

| Binary | Purpose | Status |
|--------|---------|--------|
| `ocws-sysmon` | System metrics (CPU/mem/net/bat/bt/brightness/temp) | Done |
| `ocws-clip` | Clipboard manager (cliphist + fuzzel picker) | Done |
| `ocws-shot` | Screenshot tool (grim + slurp + annotation) | Done |
| `ocws-lock` | Screen lock wrapper (swaylock) | Done |
| `ocws-kv` | Key-value persistent store (flat file) | Done |
| `ocws-brightness` | Smooth backlight control (cubic easing) | Done |
| `ocws-volume` | Smooth PulseAudio control (cubic easing) | Done |
| `ocws-notify` | Native D-Bus notification daemon | Done |
| `ocws-wallpaper` | Time-of-day wallpaper transitions | Done |
| `ocws-color` | Wallpaper palette extraction (median-cut) | Done |
| `ocws-ocr` | Screen OCR (Tesseract) | Done |
| `ocws-recorder` | Screen recording (wf-recorder wrapper) | Done |
| `ocws-live-bg` | Animated live background (GTK layer shell) | Done |
| `ocws-osd-notify` | Glassmorphic notification popup (GTK layer shell) | Done |
| `ocws-hypertile` | Dynamic tiling for labwc | Done |

- [x] **Sources Learning Library**: 22 docs in `sources-learn/` covering all dependencies + OCWS internals
- [x] **Bugfix Sweep**: Multiple critical bugs fixed
  - `ExecTerm()` replaced with `Exec("foot -e ...")` in 15 widget files (broken click actions)
  - Missing `)` added in `weather.widget` `XWeatherIcon()` and `XWeatherDesc()` (silent empty returns)
  - Division-by-zero guards added in `memory.source`, `cpu.source`, `battery.source` (NaN values on first tick)
  - `delete_kv()` same-file redirect truncation fixed in `kvstore.sh` and `kvstore-cli.sh` (data loss on delete)
  - `button.module_pill` CSS style added for 14 un-themed widgets
  - `dock.widget` wired into `ocws.config` top bar (was orphaned)

---

## Phase 1.5: SFWBar Unification (The Grand Consolidation)

*Status: PLANNING STAGE*

**Objective**: Deprecate third-party shells (`noctalia`, `crystal-dock`) by shaping our custom `sfwbar` instance to achieve absolute feature parity with both. We will retain the multi-shell switcher (Noctalia, Crystal Dock, SFWBar) as a fallback during development, but eventually phase out external dependencies to make OCWS a single, pure, highly optimized `sfwbar` ecosystem.

**Detailed Plan**: See `docs/PLAN-sfwbar-unification.md` for full implementation roadmap, gap analysis, and success criteria.

### 1. Absorb Noctalia (Top Panel Modernization)
- [ ] **Pill-Based Layouts**: Restructure `ocws.config` top bar into floating "pill" modules (separated islands) instead of a monolithic horizontal bar.
- [ ] **Glassmorphism Parity**: Port Noctalia's precise blur radius and translucency CSS tokens to SFWBar GTK3 overrides.
- [ ] **Interactive Popups**: Convert SFWBar tray icons (Network, Audio, Battery) into click-to-open GTK3 Layer Shell popups matching Noctalia's control center design.
- [ ] **Animation Support**: Leverage `sfwbar` transitions and cubic-bezier easing to match Noctalia's smooth hover states.

### 2. Absorb Crystal Dock (Bottom Panel Modernization)
- [x] **Dock Widget**: Created `dock.widget` with macOS-style magnification effect, pinned app launchers, and running app indicators. Added to bottom bar.
- [ ] **Taskbar Icon Parity**: Upgrade `sfwbar`'s bottom `taskbar` widget to support high-res icon rendering without text labels.
- [x] **Mac-like Zoom Animations**: CSS-based magnification via `padding` and `min-width`/`min-height` changes on hover.
- [x] **App Launchers**: Pinned apps in `dock-apps.widget` with icon buttons and launch actions.

### 3. Eventual Deprecation
- [ ] Remove `noctalia` and `crystal-dock` dependencies from `start-labwc.sh`.
- [ ] Remove them from `dotfiles-sync.sh` and `install.sh`.
- [ ] Remove multi-shell UI from `ocws-settings`.

---

## Phase 2: Rich Interactive Components & UI/UX

*Status: IN PROGRESS — foundation laid, polish needed*

### Notification System

- [x] `ocws-notify` — D-Bus notification daemon (replaces mako)
- [x] `ocws-osd-notify` — Glassmorphic popup overlay (gtk-layer-shell)
- [x] Unify notification styling across all sources (mako fallback, app notifications)
- [x] Notification history persistence (save to `ocws-kv`, restore on boot)
- [x] Action buttons in notifications (dismiss, open, reply)

### Media Applet

- [x] `media-player.widget` — Now playing display (playerctl)
- [x] `media.widget` — Compact controls (prev/play/next)
- [x] `ocws-media-art.sh` — Album art fetcher
- [ ] Rich media popup in Control Center with full album art display
- [ ] Live lyrics display (stretch goal)

### Calendar Widget

- [x] Interactive calendar popup (month navigation, date selection)
- [x] Integration with OCWS Glass styling
- [x] Click-to-open in calendar app

### Dynamic Workspaces

- [x] `workspaces.widget` — Pager-based workspace switching
- [x] Visual differentiation: empty vs populated workspace indicators
- [ ] Smooth indicator transitions
- [ ] Multi-monitor workspace management

### Dock Enhancement

- [x] `dock.widget` — Pinned applications with running indicators
- [ ] Drag-to-reorder support
- [ ] Auto-hide on fullscreen windows

### Theme Engine Enrichment

- [x] Wallpaper-adaptive palette extraction via `ocws-color`
- [x] Auto-generate theme from wallpaper (run `ocws-color` on wallpaper, feed into theme engine)
- [ ] Live theme preview (apply temporarily, revert on cancel)
- [x] Theme scheduling (auto-switch based on time of day)

---

## Phase 3: System Resilience & User Experience

*Status: PARTIAL — core infra done, polish needed*

### State Persistence

- [x] `ocws-kv` — Key-value store for persistent state
- [x] `ocws-state.sh` — State coordinator for ocws-daemon
- [ ] Wire ocws-daemon to save/restore all state on boot (volume, brightness, DND, theme) — low value: widgets self-correct via 2s polling. Revisit if sleep/resume causes persistent state loss.
- [ ] Daemon survives sleep/resume (ACPI suspend handling)
- [ ] Auto-recover Event Bus on system wake

### GUI Settings Manager

- [x] `ocws-settings` — Native GTK3 configuration popup with Catppuccin theme
- [ ] Blur toggle, theme switching, layout padding controls
- [ ] Replace manual `.config` file editing for common options

### Installer Hardening

- [x] `install.sh` — Basic installer with backup
- [ ] Atomic rollback on failure
- [x] User-friendly confirmation prompts
- [x] `distro/arch.sh` — Arch Linux / pacman
- [x] `distro/debian.sh` — Debian / Ubuntu / apt
- [x] `distro/fedora.sh` — Fedora / dnf

### Validation & Health

- [x] `validate.sh` — Post-install verification (25+ checks)
- [x] `health-check.sh` — System health diagnostics
- [x] `fix.sh` --dry-run — Auto-repair broken configs

---

## Phase 4: Distribution & Community Integration

*Status: NOT STARTED*

- [ ] **AUR Packaging**: `ocws-desktop-git` PKGBUILD
  - Full dependency resolution (labwc, sfwbar, fuzzel)
  - `yay -S ocws-desktop-git` one-shot install

- [ ] **Standalone Installer**: Decouple from labwc
  - Support Sway, Hyprland, other wlroots compositors
  - Auto-detect compositor, adapt config format

- [ ] **Documentation Site**: Generate from `docs/` + `sources-learn/`
  - Searchable reference
  - Interactive config builder

---

## Phase 5: Ecosystem Enrichment & Premium Features

*Status: FOUNDATION LAID — C utilities enable new capabilities*

### Desktop Widgets (Conky Replacements)

- [x] Floating desktop clocks (background layer via `desktop-clock.widget`)
- [x] Weather applets (background layer via `desktop-weather.widget`)
- [x] Hardware sensor dashboards (background layer via `desktop-sysmon.widget`)
- [ ] Interactive sticky notes (persistent via ocws-kv)
- [ ] System monitor graph widgets (CPU/mem history)

### AI/LLM Integration

- [ ] `ocws-assistant` — Floating glassmorphic AI chat widget
- [ ] Voice-activated command palette (integrated with fuzzel)
- [ ] Local LLM hooks for screen text analysis (via `ocws-ocr`)
- [ ] Clipboard intelligence (summarize, translate, explain via LLM)

### Advanced Applets

- [ ] Crypto/stock ticker plugins (API polling + chart widget)
- [ ] Spotify/MPD live lyrics display
- [ ] GitHub/GitLab notification tray (API polling)
- [ ] Weather radar map overlay
- [ ] Pomodoro timer widget

### Dynamic Wallpapers & Animations

- [x] `ocws-wallpaper` — Time-of-day transitions (built)
- [ ] Animated live wallpapers via `ocws-live-bg` (built, needs integration)
- [ ] Window open/close animations via labwc rules
- [ ] Parallax scrolling wallpapers
- [ ] Wallpaper blur on window hover

### System Enhancements

- [x] `ocws-brightness` — Smooth brightness (built)
- [x] `ocws-volume` — Smooth volume (built)
- [ ] Display management widget (via wlr-randr, multi-monitor layout presets)
- [x] Power profile switching widget (balanced/performance/powersave)
- [x] Keyboard layout indicator (via xkbcommon)
- [x] Night light toggle widget (gammastep integration)

---

## Phase 6: Dotfiles Architecture & Abstractions

*Status: PARTIAL — see per-section checkboxes below*

### 6a. Directory Structure (fix 50-file flat mess)

Current — everything flat in `dotfiles/ocws/`:
```
36 .widget files   +   3 .source files   +   5 .sh files   +   CSS   +   configs
```

Proposed — group by concern:
```
dotfiles/ocws/
├── bars/                  # Bar layout definitions
│   ├── topbar.config
│   └── bottombar.config
├── widgets/
│   ├── system/            # System metrics (battery, cpu, memory, disk, temp, network)
│   ├── media/             # Media player + controls
│   ├── controls/          # Volume, brightness, wifi, bluetooth, nightlight, power
│   ├── applets/           # Weather, calendar, clipboard
│   ├── core/              # Launcher, workspaces, clock, showdesktop, tray, dock
│   └── popups/            # Control center, notifications, quick settings, sysmon
├── sources/               # Data source definitions (scanners without UI)
├── css/                   # Split by concern: base.css, bars.css, widgets.css, popups.css
├── scripts/               # Daemon, emitter, state coordinator, helpers
├── plugins/               # Third-party user-installed widgets
└── icons/                 # Custom SVG icons
```

- [ ] Group `.widget` files into subdirectories by category
- [ ] Split `ocws.config` into `bars/topbar.config`, `bars/bottombar.config`, and `css/` files
- [ ] Move inline CSS from widget files into `css/widgets.css`
- [ ] Update all `include()` paths in configs

### 6b. Data Source / UI Split

*Status: SKIPPED — evaluated, YAGNI. Only the volume scanner is duplicated (volume-text.widget + ocws-control-center.widget). Extracting 9+ scanners into separate files for 1:1 relationships is pure overhead with no reuse benefit. The volume duplication is minor and causes no bugs.*

- [x] Evaluated — not enough reuse to justify the churn. Revisit if >50% of scanners are shared.

### 6c. Event Bus Contract

The daemon → `ocws-emit.sh` → sfwbar variable flow is implicit. 18 `ocws-emit.sh` calls exist but there's no single place listing the mapping.

- [x] Document the full event contract in `docs/events.md` mapping every IPC event to its sfwbar variable and which widgets consume it
- [x] Add `# OCWS:` comments in `ocws-daemon.sh` declaring the event namespace for each `ocws-emit.sh` call
- [x] Add a check in `test-rendering.sh` that every emitted event has a corresponding consumer

### 6d. Widget-Set Profiles

Currently `plugins.config` is one hardcoded include list. Adding or removing a widget means editing it.

- [x] Create `config/widget-sets/standard.set` (core + system metrics only — minimal)
- [x] Create `config/widget-sets/full.set` (everything — current default)
- [x] Main config just picks a set: `include("widget-sets/standard.set")`
- [x] Add profile switching support to `theme-engine.sh` (`--profile standard|full`) — low value, `ocws.config` already uses `include("widget-sets/full.set")`; editing the config is simpler than a CLI flag

### 6e. User Overlay Config

The install script copies `dotfiles/ocws/` to `~/.config/ocws/`, overwriting user edits. No separation between "platform" and "my changes".

- [x] Add `include("~/.config/ocws/user.config")` as the last line in `ocws.config` (before `#CSS`)
- [x] `user.config` can override widget positions, CSS, terminal choice, etc.
- [x] Install script never touches `user.config` — creates it only if missing
- [x] Document in a comment at the top of `ocws.config`: *"Edit user.config for personal changes — this file gets overwritten on update"*

### 6f. Widget Template System

Many text-widgets follow the same pattern: icon + value + tooltip + popup detail. The boilerplate repeats ~30 lines per widget across 15+ metric widgets.

- [ ] Evaluate whether sfwbar's `Function()` + `Config()` can generate standard text/widget patterns
- [ ] If feasible, create `templates/text-widget.tmpl` macro that reduces 30 lines → 5:

```ini
# Current (30 lines)
button "cpu-text" {
  style = "module_pill"
  label { value = "󰍛 " + Str(XCpuLoad, 0) + "%" }
  ...
}
PopUp("CpuPopup") { ... }

# Target (5 lines with template)
IncludeTemplate("text-widget.tmpl", "cpu-text",
  icon = "󰍛", value = Str(XCpuLoad, 0) + "%",
  popup_title = "CPU Monitor",
  popup_detail = "Usage: " + Str(XCpuUtilization*100, 1) + "%\n...",
  tooltip = "Click to open htop"
)
```

### 6g. Variable Contract (IPC Single Source of Truth)

**Problem**: `ocws-emit.sh` maps API names → variable names. Widgets read variable names.
These must match manually. We fixed 4 mismatches this session (battery, memory, disk).

- [x] Create `contracts/variables.ini` declaring every IPC variable:
  ```ini
  [system.volume]
  emit_name = XVolLevel
  widget_files = volume-text.widget, ocws-control-center.widget
  ```
- [ ] Auto-generate `ocws-emit.sh` case statements from the contract
- [ ] Script to validate: all widget variable references exist in contract
- [ ] Script to validate: all contract variables are defined by a scanner/source

### 6h. CSS Token Standardization

**Problem**: Colors defined 3 ways: `@define-color` in theme.css, hardcoded hex in ocws.css,
hardcoded rgba in widget files. Theme changes require editing 3+ files.

- [ ] Create `tokens.css` with all `@define-color` declarations:
  ```css
  @define-color ocws_bg #1e1e2e;
  @define-color ocws_fg #cdd6f4;
  @define-color ocws_accent #89b4fa;
  @define-color ocws_surface_alpha_50 alpha(@ocws_surface, 0.5);
  ```
- [ ] Update all widget `#CSS` sections to use `@ocws_*` tokens
- [ ] Update `ocws.config` CSS section to use tokens
- [ ] Theme engine generates `tokens.css` from INI → single file regeneration
- [ ] Remove hardcoded hex/rgba from all widget files

### 6i. Widget Schema & Validation

**Problem**: Widgets repeat scanner → export → popup → CSS pattern with no validation.
Typos in variable names or PopUp names silently break.

- [ ] Design `widget.schema.json` defining valid widget structure
- [ ] Create `ocws-validate` CLI that checks:
  - All referenced variables are defined by a scanner
  - All PopUp triggers have matching definitions
  - All CSS classes have matching rules
  - No duplicate exported button/label names
- [ ] Run validation in `install.sh` before deploying
- [ ] CI integration for PR validation

### 6j. Unified State Layer

**Problem**: State managed by 3 disconnected systems: `ocws-kv` (C), `ocws-state.sh` (bash),
`ocws-daemon.sh` (IPC only). Sleep/resume loses state.

- [ ] Design `ocws-state` daemon architecture:
  - Owns `~/.config/ocws/state/`
  - CLI: `ocws-state get/set/del/watch`
  - Auto-saves on change, auto-restores on boot
  - ACPI suspend/resume hooks
  - Streams changes to sfwbar via IPC
- [ ] Replace `ocws-state.sh` with `ocws-state` CLI
- [ ] Wire `ocws-daemon.sh` to use `ocws-state` for persistence
- [ ] Add sleep/resume handling via `systemd-suspend-hook` or `acpid`

### 6k. C Utility Shared Library

**Problem**: `ocws-brightness.c` and `ocws-volume.c` duplicate `ease_out_cubic()` and
`animate_to()`. Multiple utilities iterate `/sys/class/backlight/`.

- [ ] Extract `libocws/` with:
  - `easing.h` — `ease_out_cubic()`, `ease_in_out_cubic()`
  - `backlight.h` — `backlight_get_max()`, `backlight_set()`, `backlight_animate()`
  - `audio.h` — `audio_get_volume()`, `audio_set_volume()`, `audio_animate()`
  - `sysfs.h` — `sysfs_read_int()`, `sysfs_read_string()`, `sysfs_iter_dir()`
- [ ] Refactor `ocws-brightness.c` and `ocws-volume.c` to use shared lib
- [ ] Update `build.zig` to build `libocws` as static library

### 6l. Widget Plugin API with Lifecycle

**Problem**: Plugin system is just `include()` — no lifecycle, no dependency resolution,
no error handling. Broken widget silently takes down entire bar.

- [ ] Design `plugin.ini` manifest format:
  ```ini
  [plugin]
  name = volume-text
  [requires]
  variables = XVolLevel, XVolMuted
  provides = volume-text
  [load_order]
  after = ocws-sysmon.source
  ```
- [ ] Plugin loader resolves dependency graph before loading
- [ ] Validate variables before loading widgets
- [ ] Graceful degradation: skip broken widgets, load rest

---

## Abstraction Priority Matrix

| # | Abstraction | Effort | Impact | Bugs Prevented | Section |
|---|-------------|--------|--------|----------------|---------|
| 1 | Variable Contract | Low | HIGH | IPC mismatches | 6g |
| 2 | CSS Token Standardization | Medium | HIGH | Theme inconsistencies | 6h |
| 3 | Widget Schema & Validation | Medium | MEDIUM | Widget typos, missing deps | 6i |
| 4 | Directory Restructure | Medium | MEDIUM | Navigation, onboarding | 6a |
| 5 | Data Source / UI Split | Medium | MEDIUM | Duplicated scanners | 6b |
| 6 | Unified State Layer | High | HIGH | State loss on sleep/resume | 6j |
| 7 | C Utility Shared Library | Medium | MEDIUM | Code duplication | 6k |
| 8 | Widget Plugin API | High | MEDIUM | Silent widget failures | 6l |
| 9 | Widget-Set Profiles | Low | LOW | Config rigidity | 6d |
| 10 | User Overlay Config | Low | LOW | User edits overwritten | 6e |

---

## Project Status Summary

### Implemented (Phase 1 Complete)
- Modular widget architecture in `dotfiles/ocws/`
- Dynamic theme engine with glassmorphic CSS injection
- 15 C helper binaries built via `zig build`
- Event Bus with full namespace coverage
- Plugin autoloader
- Key-value persistent store
- 22 learning docs in `sources-learn/`
- Post-install validation and health checks

### In Progress (Phase 2)
- Notification system polish (ocws-notify + ocws-osd-notify)
- Rich media applet with album art
- Calendar widget
- Theme engine enrichment (wallpaper-adaptive, scheduling)

### Gaps to Close (Phase 3)
- Daemon resilience on sleep/resume
- State persistence wiring (ocws-daemon + ocws-kv)
- GUI settings manager

### Not Started (Phase 4-5)
- AUR packaging
- Standalone installer
- Desktop widgets, AI integration, advanced applets

### Proposed (Phase 6 — Architecture Abstractions)
- Directory restructure (flat → grouped by concern)
- Variable contract (IPC single source of truth)
- CSS token standardization
- Widget schema & validation
- Unified state layer with sleep/resume
- C utility shared library
- Widget plugin API with lifecycle
- Widget templates: evaluate `Function()` + `Config()` for reducing boilerplate

### Delivered (Phase 6)
- Event contract: `docs/events.md` documenting all daemon→sfwbar IPC mappings
- Widget-set profiles: `full.set` + `standard.set` created, config uses `include("widget-sets/full.set")`
- User overlay: `include("user.config")` with install-guard already in place

### Skipped (Phase 6 — YAGNI)
- Data source split: no reuse benefit, 1:1 scanner→widget ratios
- Theme-engine profile switching: CLI flag over a config edit is over-engineering

### Proposed (Phase 7 — C-Native Transition)
**Goal:** Gradually rewrite Bash script utilities and core functions into native C code for better performance, lower latency, and reduced process-forking overhead.
- **`ocws-brokerd`**: C-native DBus state daemon replacing `ocws-daemon.sh` and `ocws-state.sh` for robust state persistence and event handling.
- **`ocws-config`**: C-based configuration parser replacing the `theme-engine.sh` bash script. This will use a standard format (like YAML or INI) and natively render templates without needing sed/awk.
- **`ocws-ipc` / `ocws_ipc.h`**: Type-safe C IPC library replacing `ocws-emit.sh`.
- **`ocws-network-menu` & `ocws-bluetooth-menu`**: C-native fuzzel wrappers replacing `scripts/actions/wifi-menu.sh` and `scripts/actions/bluetooth-menu.sh` using `libnm` (NetworkManager) and `bluez` DBus interfaces.
- **`ocws-launcher`**: A unified C binary replacing `launcher.sh`, `fuzzel-emoji.sh`, and `fuzzel-calc.sh`.
- **Component API**: Dynamic UI injection via DBus instead of static `.widget` includes.
- **Dependency Reduction**: Replace heavy external packages with native C implementations:
  - Replace `inotify-tools` (`inotifywait`) by using Linux's native `inotify(7)` API in `ocws-brokerd`.
  - Replace `imagemagick` (`convert`) in media widget updaters by using lightweight C image manipulation (e.g., `stb_image` or `cairo`).
  - Replace `xdotool` in workspace scripts by using Wayland's `wlr-foreign-toplevel-management` or `wlr-layer-shell` protocols natively in C.
  - Replace `wireplumber` CLI (`wpctl`) by hooking directly into the PipeWire/WirePlumber C API for audio controls.

---

## Phase 7: Bash Script Enrichment & C Rewrite Roadmap

*Status: PLANNING*

### 7a. Bash Script Enrichment (Short-term)

Improve existing bash scripts with better error handling, portability, and features.

#### Critical Scripts (Enrich First)

| Script | Current State | Enrichment Plan |
|--------|---------------|-----------------|
| `ocws-emit.sh` | 56 lines, basic case statement | Add `--dry-run`, `--verbose`, batch mode, config file support |
| `ocws-state.sh` | 280 lines, JSON via jq | Add atomic writes, backup rotation, state validation |
| `ocws-daemon.sh` | Event listener | Add reconnection logic, graceful shutdown, signal handling |
| `ocws-plugin-loader.sh` | Dynamic include generator | Add dependency resolution, validation, error reporting |

#### Utility Scripts (Add New)

| Script | Purpose | Priority | Status |
|--------|---------|----------|--------|
| `ocws-validate.sh` | Post-install validation (25+ checks) | HIGH | Done |
| `ocws-health.sh` | System health diagnostics | HIGH | Done |
| `ocws-icon-picker.sh` | Pick icon theme using fuzzel picker | HIGH | Done |
| `ocws-icon-downloader.sh` | Download and install icon themes | HIGH | Done |
| `ocws-backup.sh` | Configuration backup/restore with rotation | MEDIUM | Planned |
| `ocws-update.sh` | Self-update from git | MEDIUM | Planned |
| `ocws-debug.sh` | Debug mode with verbose logging | LOW | Planned |

#### Action Scripts (Added)

| Script | Purpose | File |
|--------|---------|------|
| `mic.sh` | Microphone control (mute toggle, volume, list sources) | `scripts/actions/mic.sh` |
| `dnd.sh` | Do Not Disturb toggle with Event Bus IPC emit | `scripts/actions/dnd.sh` |
| `display.sh` | Display layout management (wlr-randr: list, single, mirror, save) | `scripts/actions/display.sh` |
| `vpn.sh` | VPN status/control (connect, disconnect, toggle, list) | `scripts/actions/vpn.sh` |
| `ocws-display.sh` | Display layout persistence with Event Bus IPC | `scripts/ocws-display.sh` |

#### Action Scripts (Enrich Existing)

| Script | Enrichment |
|--------|------------|
| `audio.sh` | Add `get` command, volume normalization, device selection |
| `brightness.sh` | Add `get` command, smooth transitions, multi-monitor |
| `screenshot.sh` | Add annotation, upload, delay timer |
| `clipboard.sh` | Add search, delete, export/import |
| `network.sh` | Add WiFi scanning, connect/disconnect, QR code |
| `workspace.sh` | Add move-to-workspace, workspace naming |

### 7b. C Rewrite Roadmap (Medium-term)

Replace performance-critical and frequently-called bash scripts with C implementations.

#### Priority Matrix (Effort vs Impact)

| # | Bash Script | Lines | C Binary | Effort | Impact | Risk | Rationale |
|---|-------------|-------|----------|--------|--------|------|-----------|
| 1 | `ocws-emit.sh` | ~120 | `ocws-emit` | Low | High | Low | IPC critical path, forked on every event. Trivial C port (socket write) |
| 2 | `ocws-daemon.sh` | ~350 | `ocws-brokerd` | High | High | Medium | Event bus loop: inotify + pactl + playerctl. C eliminates race conditions |
| 3 | `audio.sh` | ~124 | Use `ocws-volume` | Low | High | Low | C binary exists, wire action script to call it directly |
| 4 | `brightness.sh` | ~119 | Use `ocws-brightness` | Low | High | Low | Same -- call C binary from action script |
| 5 | `theme-engine.sh` | ~636 | `ocws-theme` | High | High | Medium | Largest bash file. INI parser + template renderer + file deployer |
| 6 | `ocws-plugin-loader.sh` | ~80 | `ocws-plugin` | Low | Medium | Low | Scan dir, generate include list. Simple file I/O |
| 7 | `network.sh` | ~211 | `ocws-network` | Medium | Medium | Low | nmcli wrapper + BT control. Netlink would be more robust |
| 8 | `screenshot.sh` | ~80 | Use `ocws-shot` | Low | Medium | Low | C binary exists, wire to call it |
| 9 | `ocws-state.sh` | ~100 | Merge into `ocws-kv` | Low | Low | Low | Thin wrapper, absorb into C |
| 10 | `mic.sh` | ~80 | `ocws-mic` | Low | Low | Low | Simple wpctl wrapper |
| 11 | `display.sh` + `ocws-display.sh` | ~200 | `ocws-display` | Medium | Low | Low | wlr-randr wrapper, could use wlr-output-management protocol |
| 12 | `dnd.sh` | ~80 | Merge into `ocws-notify` | Low | Low | Low | Just IPC emit + dbus call |
| 13 | `vpn.sh` | ~130 | `ocws-vpn` | Medium | Low | Low | nmcli wrapper + status polling |
| 14 | `power-menu.sh` | ~40 | `ocws-power` | Low | Low | Low | systemctl wrapper |
| 15 | `clipboard.sh` | ~30 | Use `ocws-clip` | Low | Low | Low | C binary exists |
| 16 | `ocws-network-bandwidth.sh` | ~80 | Merge into `ocws-sysmon` | Low | Low | Low | Already handled by ocws-sysmon |
| 17 | `window.sh` | ~60 | Extend `ocws-hypertile` | Medium | Low | Low | wlr-foreign-toplevel protocol |
| 18 | `workspace.sh` | ~50 | `ocws-workspace` | Low | Low | Low | labwc IPC commands |
| 19 | `fuzzel-emoji.sh` | ~40 | `ocws-emoji` | Low | Low | Low | Read emoji file, pipe to fuzzel |
| 20 | `fuzzel-calc.sh` | ~20 | N/A (skip) | -- | -- | -- | Too trivial, bc is fine |
| 21 | `backup.sh`, `restore.sh`, `clean.sh` | ~150 | N/A (skip) | -- | -- | -- | Shell is appropriate for file ops |
| 22 | `debug-labwc.sh`, `start-labwc.sh` | ~60 | N/A (skip) | -- | -- | -- | Launcher scripts, no benefit in C |
| 23 | `font-scale.sh` | ~60 | `ocws-font-scale` | Low | Low | Low | Multi-file font config update |
| 24 | `media-art.sh` | ~80 | `ocws-media-art` | Medium | Low | Low | HTTP fetch + image processing |

#### Phase 7a: C IPC Core (Weeks 1-2)

Replace the IPC layer (ocws-emit.sh + ocws-daemon.sh) with a single C daemon.

```
ocws-brokerd/
├── main.c              # Event loop, signal handling
├── emit.c / emit.h     # ocws-emit replacement (Unix socket write)
├── watchers/
│   ├── inotify.c       # Backlight, battery, thermal monitoring
│   ├── pipewire.c      # Volume/audio events via PipeWire API
│   └── playerctl.c     # MPRIS media player events
├── ipc.c / ipc.h       # IPC protocol (Unix socket or D-Bus)
└── build.zig           # Standalone build target
```

- [ ] `ocws-emit` C binary: writes to sfwbar scanner socket. Same CLI: `ocws-emit <Namespace.Key> <Value>`. Replaces ~120 lines of bash with ~60 lines of C.
- [ ] `ocws-brokerd` C daemon: inotify + PipeWire + MPRIS watchers in one process. Replaces ~350 lines of bash loop/process-spawning with signal-safe C event loop.
- [ ] Wire `ocws-daemon.sh` to use ocws-brokerd when available, fall back to bash
- [ ] Add systemd user service for ocws-brokerd

- [ ] `ocws_ipc.h` shared header: type-safe IPC helpers used by all C binaries:
  ```c
  // Emit a value to the Event Bus
  void ocws_emit(const char *ns, const char *key, const char *value);

  // Subscribe to state changes
  typedef void (*ocws_handler_t)(const char *key, const char *value);
  int ocws_subscribe(const char *ns, ocws_handler_t handler);
  ```

#### Phase 7b: Action Script Rewrites (Weeks 3-6)

Rewrite action scripts one by one, keeping bash fallbacks until proven.

| Week | Binary | Bash Replaced | Lines Saved |
|------|--------|---------------|-------------|
| 3 | `ocws-mic` | mic.sh | 80 |
| 3 | `ocws-network` | network.sh | 211 |
| 4 | `ocws-display` | display.sh + ocws-display.sh | 200 |
| 4 | `ocws-vpn` | vpn.sh | 130 |
| 5 | `ocws-power` | power-menu.sh | 40 |
| 5 | `ocws-emoji` | fuzzel-emoji.sh | 40 |
| 5 | `ocws-workspace` | workspace.sh | 50 |
| 6 | `ocws-plugin` | ocws-plugin-loader.sh | 80 |
| 6 | `ocws-theme` | theme-engine.sh | 636 |

Total: ~1,467 lines of bash replaced with C.

#### Phase 7c: Shared Library Extraction (Week 7)

- [ ] `libocws/` shared library:
  - `easing.h` — `ease_out_cubic()`, `ease_in_out_cubic()` (already duplicated in brightness + volume)
  - `sysfs.h` — `sysfs_read_int()`, `sysfs_read_string()`, `sysfs_iter_dir()`
  - `ipc.h` — `ocws_emit()`, `ocws_subscribe()`, `ocws_brokerd_connect()`
  - `util.h` — `ocws_strdup()`, `ocws_read_file()`, `ocws_write_file()`
- [ ] Refactor ocws-brightness, ocws-volume to use libocws
- [ ] Update build.zig: build libocws as static lib, link all binaries
- [ ] Add `#include "libocws/ipc.h"` to all new C binaries

#### Phase 7d: Migration Strategy

- Each rewrite keeps the bash script as fallback: C binary takes priority, bash runs if C not found
- Install script deploys both versions during transition
- No single point of failure: if ocws-brokerd crashes, widgets still work (they poll independently)
- Action scripts call C binary first: `command -v ocws-mic && exec ocws-mic "$@" || exec mic.sh "$@"`
- Phase gate: all C binaries must pass the same test suite as bash originals before bash fallback is removed

### 7c. C Rewrite Implementation Strategy

#### Shared Library (`libocws/`)

Extract common utilities into a shared library:

```
src/libocws/
├── easing.h          # ease_out_cubic(), ease_in_out_cubic()
├── sysfs.h           # sysfs_read_int(), sysfs_read_string()
├── config.h          # ini_parse(), xml_parse(), css_parse()
├── ipc.h             # sfwbar_emit(), dbus_emit()
├── process.h         # process_exec(), process_kill()
└── file.h            # file_atomic_write(), file_lock()
```

#### Build Integration

Update `build.zig` to build shared library:

```zig
const lib = b.addStaticLibrary("ocws", "src/libocws/lib.zig");
lib.linkSystemLibrary("gtk+-3.0");
lib.linkSystemLibrary("glib-2.0");
```

#### Migration Strategy

1. **Phase 1**: Create `libocws/` with shared utilities
2. **Phase 2**: Rewrite `ocws-emit.sh` -> `ocws-emit.c` (most called)
3. **Phase 3**: Rewrite `ocws-daemon.sh` -> `ocws-daemon.c` (longest running)
4. **Phase 4**: Integrate `ocws-state.sh` into `ocws-kv`
5. **Phase 5**: Rewrite remaining scripts based on usage patterns

### 7d. Bash Script Quality Improvements

#### Add `set -euo pipefail` to All Scripts

Currently 14 scripts have no shell options. Fix:

```bash
#!/bin/bash
set -euo pipefail
```

#### Add Proper Error Handling

```bash
# Before
some_command

# After
if ! some_command; then
    echo "Error: some_command failed" >&2
    exit 1
fi
```

#### Add Input Validation

```bash
# Before
VAR="$1"

# After
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <variable> <value>" >&2
    exit 1
fi
VAR="$1"
```

#### Add Logging Support

```bash
# Add to all scripts
OCWS_LOG="${OCWS_LOG:-/tmp/ocws.log}"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$OCWS_LOG"; }
```

### 7e. Testing Strategy

#### Unit Tests for Bash Scripts

Create `tests/` directory:

```
tests/
├── test-ocws-emit.sh
├── test-ocws-state.sh
├── test-ocws-plugin-loader.sh
├── test-font-scale.sh
└── run-all-tests.sh
```

#### Integration Tests for C Utilities

```bash
# Test ocws-emit.c
./zig-out/bin/ocws-emit System.Volume 75
sfwbar -R "GetVal XVolLevel" | grep -q "75"

# Test ocws-kv.c
./zig-out/bin/ocws-kv set test key value
./zig-out/bin/ocws-kv get test key | grep -q "value"
```

---

---

## Phase 8: Zig Superpowers & Next-Gen Distribution

*Status: IN PROGRESS*

Because OCWS already uses `build.zig` as its build system, we have unlocked capabilities far beyond traditional C/Make projects. This phase outlines how we can leverage Zig to make OCWS a robust, standalone, deploy-anywhere Wayland shell.

### 8a. Unified Binary (Single Entry Point)
- [x] Merge all 15 `ocws-*` binaries into one `ocws` with subcommands (`ocws shot`, `ocws clip`, `ocws volume`, `ocws kv set/get`)
- [x] Reduces install footprint from 15 binaries to 1
- [x] Shared initialization code (logging, config loading) in one place
- [x] Migration: `ocws shot` still calls same C code, just different entry point

### 8b. Static Binaries (Zero-Dependency Distribution)
- [x] Build with `-Dtarget=x86_64-linux-musl` for fully static binaries
- [x] Single binary file, no package manager required for end-users
- [ ] Distribute via `curl | tar` or AppImage without runtime deps
- [ ] Test: verify static binary runs on fresh Ubuntu/Arch/Fedora without installing anything

### 8c. Cross-Compilation (ARM / RISC-V / WASM)
- [x] Add CI pipeline: `zig build -Dtarget=aarch64-linux-gnu` for Raspberry Pi 4/5
- [x] Add CI pipeline: `zig build -Dtarget=riscv64-linux-gnu` for RISC-V boards
- [ ] Add CI pipeline: `zig build -Dtarget=wasm32-wasi` for browser-based widgets
- [x] One-command cross-compile: no cross-gcc, no multilib, no sysroot hacking
- [ ] Target: OCWS runs on PinePhone, Librem 5, StarFive VisionFive

### 8d. Zig-Native Modules (Incremental Rewrite)
- [ ] Rewrite config parser (`theme-engine.sh` → `ocws-theme.zig`) using Zig's comptime parsing
- [ ] Rewrite event loop (`ocws-daemon.sh` → `ocws-brokerd.zig`) with memory-safe async
- [ ] Use `@cImport()` to seamlessly call existing C code from Zig modules
- [ ] Error unions (`!void`) prevent memory leaks in new code
- [ ] `defer` statements for automatic cleanup (no manual `free()` calls)

### 8e. Compile-Time Asset Embedding (`comptime`)
- [ ] Use `@embedFile()` to bake default configs, icons, themes into binary
- [ ] Binary becomes self-sufficient — no missing `/usr/share/ocws/` failures
- [ ] Fallback config embedded: if `~/.config/ocws/` missing, use built-in defaults
- [ ] Theme templates embedded: generate themes without external template files

### 8f. Build-From-Source Package Manager
- [ ] Single `build.zig.zon` fetches all C dependencies automatically
- [ ] No `-dev` packages required: `zig build` fetches wayland, gtk, tesseract headers
- [ ] Reproducible builds: same Zig version = identical binaries everywhere
- [ ] `zig build -Drelease` for optimized release builds
- [ ] `zig build test` runs C unit tests via Zig's test runner

### 8g. Testing Framework (C Unit Tests via Zig) - DONE
- [x] Add `test "backlight easing" { ... }` blocks in C files using `@import("std").testing`
- [x] `zig build test` runs all C unit tests in one pass
- [x] No separate test framework (no cmocka, no check) — Zig handles it
- [ ] CI integration: tests must pass before merge

### 8h. SIMD Optimizations (Hot Paths)
- [ ] Rewrite image processing in `ocws-color.c` (median-cut palette extraction) using Zig SIMD
- [ ] Rewrite OCR preprocessing in `ocws-ocr.c` (grayscale, threshold) with vectorized ops
- [ ] Rewrite wallpaper blur/transitions in `ocws-live-bg.c` with SIMD
- [ ] 4-8x speedup for image operations on x86_64/ARM NEON

### 8i. Nightly Auto-Builds (GitHub Actions)
- [x] GitHub Actions workflow: build for x86_64, aarch64, riscv64 on every push
- [x] Artifacts: static binaries attached to each release
- [ ] Automated testing: boot test on QEMU ARM before release
- [ ] `nightly.ocws.dev` with latest binaries

### 8j. Plugin System (Dynamic Loading)
- [ ] Zig handles `.so` loading: `std.dynamic_loader.openLib()`
- [ ] User plugins in `~/.config/ocws/plugins/*.so`
- [ ] Plugin API: `ocws_plugin_init()`, `ocws_plugin_destroy()`, `ocws_plugin_emit()`
- [ ] Sandboxed execution: plugins can't crash main process

### 8k. WASM Plugins (Sandboxed User Scripts)
- [ ] Build `ocws-wasm-runner` targeting `wasm32-wasi`
- [ ] User scripts in `~/.config/ocws/scripts/*.wasm`
- [ ] Sandboxed: no filesystem/network access unless explicitly granted
- [ ] Use case: custom widgets, data transformers, AI inference

### 8l. Fast Incremental Builds
- [ ] Zig tracks C file changes at function level — only recompile changed functions
- [ ] `zig build` finishes in <2s for incremental builds (vs 30s+ with make)
- [ ] Developer workflow: edit → build → test in <3 seconds

### 8m. Cross-Dependency Fetching (build.zig.zon)
- [x] Declare all C deps in `build.zig.zon`:
  ```zig
  .{
      .name = "ocws",
      .dependencies = .{
          .wayland = .{ .url = "https://...", .hash = "..." },
          .gtk = .{ .url = "https://...", .hash = "..." },
          .tesseract = .{ .url = "https://...", .hash = "..." },
      },
  }
  ```
- [x] `zig build` fetches, compiles, links — no system packages needed
- [x] Reproducible: same `build.zig.zon` = same build on any machine

---

## Risk Mitigation

1. **Delete legacy cruft** before adding new features
2. **Simplest solution that works** — avoid premature abstraction
3. **Implement one component at a time** with clear boundaries
4. **Automate testing** for all integrations
5. **Document decisions** inline with `# OCWS:` comments
6. **Phase 6 abstractions** — Evaluate each before implementing; low-effort/high-impact items (Variable Contract, CSS Tokens, Config Validation) ship first

## Development Timeline

| Phase | Focus | Status |
|-------|-------|--------|
| Phase 1 | Platform consolidation | Complete |
| Phase 2 | Rich components | In Progress |
| Phase 3 | Resilience & UX | Partial |
| Phase 4 | Distribution | Not Started |
| Phase 5 | Ecosystem enrichment | Foundation Laid |
| Phase 6 | Architecture abstractions | Partial (3 delivered, 2 skipped) |
| Phase 7 | Bash enrichment & C rewrite | Planning |
| Phase 8 | Zig superpowers & next-gen distribution | Planning |
