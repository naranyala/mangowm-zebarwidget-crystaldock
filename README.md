# labwc + Zebar + crystal-dock

A complete Wayland desktop environment built on **labwc** (Openbox-inspired compositor), **zebar** (HTML/CSS/JS widget panels), and **crystal-dock** (Wayland dock). Ships with interactive theme management, 25+ automation scripts, and a full GTK3/GTK4 theming pipeline.

---

## Quick Start

```bash
# 1. Build labwc from source
./download-labwc.sh --install

# 2. Install all dotfiles (with backup)
./dotfiles/install.sh

# 3. Launch from TTY
./scripts/start-labwc.sh
```

Or use the interactive reconfigure CLI:
```bash
./scripts/reconfigure.sh
```

---

## What's Included

### Core Components

| Component | Role | Config Location |
|-----------|------|-----------------|
| **labwc** | Wayland compositor (Openbox-inspired) | `~/.config/labwc/` |
| **zebar** | HTML/CSS/JS widget panels | `~/.config/zebar/` |
| **crystal-dock** | Wayland dock | autostart |
| **foot** | Wayland terminal | autostart |
| **rofi** | Application launcher | keybindings |

### Feature Set

- **Interactive theme picker** — 10+ predefined themes with color previews
- **GTK3/GTK4 theming** — Full settings, CSS overrides, cursor/icon/font management
- **Font system** — UI, monospace, CJK, Nerd Fonts with profile-based install
- **Wallpaper manager** — Random rotation, download sources, daemon mode
- **25+ automation scripts** — Backup, restore, validate, fix, diagnostics
- **Action scripts** — Screenshot, clipboard, audio, brightness, power menu
- **Keybinding presets** — Multiple layout options
- **Widget system** — Main bar + 4 alternative widget themes

---

## Project Structure

```
labwc-zebarwidget-crystaldock/
├── README.md                          # This file
├── download-labwc.sh                  # Build labwc from source
│
├── config/labwc/                      # Reference config copies
│   ├── rc.xml                         # Keybindings & window rules
│   ├── autostart                      # Startup commands
│   ├── environment                    # Environment variables
│   ├── menu.xml                       # Desktop right-click menu
│   ├── themerc-override               # Window decoration theme
│   └── startup-wallpaper.sh           # Wallpaper launcher
│
├── dotfiles/                          # Installable configuration
│   ├── install.sh                     # Main installer
│   ├── README.md                      # Dotfiles documentation
│   ├── labwc/                         # labwc config files
│   │   ├── rc.xml                     # 100+ keybindings, window rules
│   │   ├── autostart                  # Shell script (wallpaper, dock, zebar, etc.)
│   │   ├── environment                # Wayland/GTK/Qt env vars
│   │   ├── menu.xml                   # Desktop menu with 15+ entries
│   │   ├── themerc-override           # Window decoration colors
│   │   ├── startup-wallpaper.sh       # Random wallpaper via swaybg
│   │   └── presets/                   # Keybinding presets
│   │       ├── default.xml
│   │       └── super.xml
│   ├── gtk/                           # GTK3/GTK4 theme configuration
│   │   ├── gtk3-settings.ini          # GTK3 theme, icons, cursor, fonts
│   │   ├── gtk4-settings.ini          # GTK4 theme settings
│   │   ├── gtk.css                    # CSS overrides (rounded corners, etc.)
│   │   └── theme-profiles/            # 7 predefined GTK theme profiles
│   │       ├── arc-dark
│   │       ├── breeze / breeze-dark
│   │       ├── catppuccin-mocha / catppuccin-macchiato
│   │       ├── nordic
│   │       └── pocillo-dark
│   ├── zebar/                         # Widget configuration
│   │   ├── main/                      # Primary statusbar
│   │   │   ├── index.html             # Full statusbar with providers
│   │   │   ├── style.css              # Catppuccin Mocha theme
│   │   │   └── zpack.json             # Widget pack manifest
│   │   ├── settings.json              # Zebar startup config
│   │   ├── launcher.sh                # Widget launcher script
│   │   └── widgets/                   # Alternative widget themes
│   │       ├── compact/               # Space-optimized bar
│   │       ├── detailed/              # 3x2 grid dashboard
│   │       ├── minimalist/            # Gradient background
│   │       └── system/                # Full system monitor
│   ├── wallpaper                      # Wallpaper manager script
│   └── wallpaper-sources.txt          # 22 Unsplash download URLs
│
├── scripts/                           # 25+ automation scripts
│   ├── reconfigure.sh                 # Interactive CLI (main entry point)
│   ├── validate.sh                    # 8-category validation
│   ├── fix.sh                         # Auto-fix permissions, symlinks, config
│   ├── status.sh                      # Live status dashboard
│   ├── backup.sh                      # Timestamped backup with rotation
│   ├── restore.sh                     # Restore from backup
│   ├── diagnostics.sh                 # Deep system report
│   ├── theme-picker.sh                # Interactive visual theme picker
│   ├── theme.sh                       # Theme manager (apply GTK/labwc/cursor)
│   ├── themes.sh                      # Unified theme CLI
│   ├── download-themes.sh             # Download GTK/icon/cursor/font resources
│   ├── keybinds.sh                    # View/add/remove keybindings
│   ├── keybind-presets.sh             # Keybinding preset manager
│   ├── widget-manager.sh              # Widget install/remove/create
│   ├── widget-actions.sh              # Widget action scripts
│   ├── start-labwc.sh                 # Launch with pre-flight checks
│   ├── start-redshift.sh              # Start screen protection
│   ├── toggle-natural-scroll.sh       # Toggle touchpad natural scroll
│   ├── install-deps.sh                # Install system dependencies
│   ├── update.sh                      # Update labwc from source
│   ├── quick.sh                       # Shortcuts for common ops
│   ├── dotfiles-sync.sh               # Sync dotfiles with project
│   ├── clean.sh                       # Clean build artifacts
│   ├── setup.sh                       # First-time setup
│   └── actions.sh                     # Unified action entry point
│       └── actions/                   # Individual action scripts
│           ├── audio.sh               # Volume, mute, sink switch
│           ├── brightness.sh          # Brightness control
│           ├── clipboard.sh           # Clipboard manager
│           ├── launcher.sh            # Apps, calc, emoji, color picker
│           ├── network.sh             # WiFi/BT toggle, status
│           ├── power-menu.sh          # Shutdown, reboot, logout
│           ├── quick-settings.sh      # Dark mode, DND, night mode
│           ├── screenshot.sh          # Full/area/window screenshots
│           ├── window.sh              # Snap, float, fullscreen
│           └── workspace.sh           # Switch/move workspaces
│
├── themes/                            # Theme profile definitions
│   ├── catppuccin-mocha.ini           # Warm pastel dark
│   ├── dracula.ini                    # Purple accent dark
│   ├── nord.ini                       # Arctic blue
│   └── tokyo-night.ini                # Neon blue/purple
│
├── widgets/                           # Enhanced widget themes
│   ├── main/                          # Enhanced main statusbar
│   ├── compact/                       # Compact bar variant
│   ├── detailed/                      # Detailed grid view
│   └── minimalist/                    # Minimal gradient
│
├── docs/                              # Documentation
│   ├── configuration.md               # Full configuration reference
│   └── getting-started.md             # Setup guide
│
├── examples/                          # Example configurations
├── templates/                         # Template files
├── build/                             # Build artifacts
└── .gitignore                         # Git ignore rules
```

---

## Scripts Reference

### Main Entry Points

| Script | Description |
|--------|-------------|
| `reconfigure.sh` | **Interactive CLI** — menu-driven reconfiguration with backup |
| `install.sh` | Full installer (labwc + GTK + zebar + scripts) |
| `start-labwc.sh` | Launch labwc with dependency checks |
| `validate.sh` | 8-category validation (binaries, configs, themes, etc.) |
| `fix.sh` | Auto-fix permissions, symlinks, missing configs |

### Theme Management

| Script | Description |
|--------|-------------|
| `theme-picker.sh` | Interactive visual theme picker with color previews |
| `theme.sh` | Theme manager (apply labwc + GTK + cursor + fonts) |
| `themes.sh` | Unified theme CLI (profiles, sets, overrides) |
| `download-themes.sh` | Download GTK/icon/cursor/font resources |

```bash
# Theme picker (interactive)
theme-picker              # or: theme-picker pick

# Quick apply
theme-picker apply catppuccin-mocha

# List themes
theme-picker list

# Download all resources
download-themes.sh all

# Download fonts only
download-themes.sh fonts

# Install font profile
download-themes.sh font-profile dev
```

### Widget Management

| Script | Description |
|--------|-------------|
| `widget-manager.sh` | Install/remove/create widget themes |
| `widget-actions.sh` | Widget action scripts |

```bash
# List widgets
widget-manager list

# Install widget
widget-manager install compact

# Set as main bar
widget-manager enable detailed

# Create new widget
widget-manager create my-widget
```

### System Management

| Script | Description |
|--------|-------------|
| `backup.sh` | Timestamped backup with rotation |
| `restore.sh` | Restore from backup (with dry-run) |
| `diagnostics.sh` | Deep system report |
| `status.sh` | Live status dashboard |
| `update.sh` | Update labwc from source |
| `install-deps.sh` | Install system dependencies |

### Actions

```bash
# Via unified entry point
actions.sh screenshot area
actions.sh audio mute
actions.sh brightness up
actions.sh power-menu
actions.sh clipboard pick
actions.sh network wifi-toggle
actions.sh window snap-left
actions.sh workspace switch 3

# Via quick shortcuts
quick theme-picker
quick theme-apply nord
quick backup
quick validate
quick fix
```

---

## Keybindings

### System
| Key | Action |
|-----|--------|
| `Super+R` | Reload config |
| `Super+Q` / `Alt+F4` | Close window |
| `Super+M` | Exit labwc |

### Launchers
| Key | Action |
|-----|--------|
| `Super+Return` | Terminal (foot) |
| `Alt+D` | App launcher (rofi) |
| `Alt+Tab` | Window switcher |
| `Alt+X` | Run command |
| `Alt+F5` | Power menu |

### Window Management
| Key | Action |
|-----|--------|
| `Alt+E` | Toggle floating |
| `Alt+F` | Toggle fullscreen |
| `Super+A` | Toggle maximize |
| `Alt+Space` | Root menu |
| `Ctrl+Alt+Arrows` | Window snapping |

### Workspaces
| Key | Action |
|-----|--------|
| `Alt+1-9` | Switch workspace |
| `Super+Shift+1-9` | Move window to workspace |
| `Ctrl+Alt+Left/Right` | Next/prev workspace |

### Media
| Key | Action |
|-----|--------|
| `XF86AudioRaise/Lower` | Volume |
| `XF86AudioMute` | Toggle mute |
| `XF86MonBrightness` | Brightness |
| `Print` | Screenshot (area) |
| `Alt+Print` | Screenshot (full) |
| `Ctrl+Shift+V` | Clipboard history |

See [docs/configuration.md](docs/configuration.md) for complete keybinding reference.

---

## Theming

### 10 Predefined Themes

| Theme | Style | Base | Accent |
|-------|-------|------|--------|
| catppuccin-mocha | Warm pastel dark | `#1e1e2e` | `#89b4fa` |
| nord | Arctic blue | `#2e3440` | `#88c0d0` |
| dracula | Purple accent | `#282a36` | `#bd93f9` |
| tokyo-night | Neon blue | `#1a1b26` | `#7aa2f7` |
| arc-dark | Material dark | `#262e38` | `#3498db` |
| breeze-dark | KDE dark | `#23282d` | `#3daee9` |
| everforest | Green earthy | `#2f3530` | `#a3be8c` |
| gruvbox | Retro warm | `#282828` | `#b8bb26` |
| rose-pine | Muted rose | `#191724` | `#ebbcba` |
| solarized-light | Classic light | `#fdf6e3` | `#268bd2` |

### What Gets Themed

- **labwc** — Window decorations (themerc-override)
- **GTK3/GTK4** — Theme, icons, cursors, fonts
- **Statusbar** — CSS variables for colors
- **Environment** — Cursor theme, font rendering

```bash
# Interactive picker
theme-picker

# Quick apply
theme-picker apply catppuccin-mocha

# Preview colors
theme-picker preview nord
```

---

## Zebar Statusbar

The statusbar includes:
- **Workspaces** (1-9) with active indicator
- **Real-time clock** with date
- **CPU/Memory** usage bars
- **Network** status (WiFi/Ethernet)
- **Volume** indicator with mute detection
- **Battery** level with charging state
- **Night mode** toggle

### Widget Variants

| Widget | Description |
|--------|-------------|
| `main` | Full-featured statusbar (default) |
| `compact` | Space-optimized single-line bar |
| `minimalist` | Gradient background design |
| `detailed` | 3x2 grid with comprehensive data |
| `system` | Full system monitoring dashboard |

---

## Installation

### Prerequisites

- **labwc** — Build with `./download-labwc.sh` or install via package manager
- **zebar** — Widget framework
- **crystal-dock** — Wayland dock
- **foot** — Terminal
- **rofi** — Launcher
- **swaybg** — Wallpaper setter

### Install Dependencies

```bash
./scripts/install-deps.sh
```

### Install Dotfiles

```bash
./dotfiles/install.sh
```

This installs:
- labwc config → `~/.config/labwc/`
- GTK3/GTK4 settings → `~/.config/gtk-3.0/` and `~/.config/gtk-4.0/`
- Zebar widgets → `~/.config/zebar/`
- Scripts → `~/.local/bin/`
- Wallpaper script → `~/.local/bin/wallpaper`
- Session file → `/usr/share/wayland-sessions/labwc.desktop`

### Launch

```bash
# From TTY (Ctrl+Alt+F2)
./scripts/start-labwc.sh

# Or select labwc from display manager
```

---

## Backup & Restore

```bash
# Create backup
backup.sh

# List backups
restore.sh

# Restore from latest
restore.sh

# Restore specific backup
restore.sh 20260703-120000
```

Backups are stored in `~/.config/labwc-backups/` with automatic rotation (keeps last 5).

---

## Documentation

- [Configuration Guide](docs/configuration.md) — Full keybinding reference, config files, themes
- [Getting Started](docs/getting-started.md) — Setup guide, prerequisites, troubleshooting

---

## License

This project is provided as-is for personal use.
