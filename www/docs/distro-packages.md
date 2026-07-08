# Package Availability Across Distributions

Every binary referenced at runtime by the OCWS dotfiles — shell mode scripts, autostart daemons, action scripts, widget configs — mapped to distro repos.

## Legend

| Mark | Meaning |
|---|---|
|  | In default repos |
|  AUR/COPR/OBS | In unofficial user repos, semi-automated |
|  stable /  testing | Not in that branch |
|  build | Not packaged anywhere — must build from source |
|  | Not available at all |

## Core Stack

| Binary | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| labwc |  community |  backports+ |  |  |
| sfwbar |  community |  stable /  testing |  COPR |  |
| rofi-wayland |  community |  |  |  |
| fuzzel |  community |  stable /  testing |  |  |
| foot |  community |  backports+ |  |  |
| mako |  community |  (`mako-notifier`) |  |  |



## Clipboard & Screenshots

| Binary | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| wl-clipboard |  |  |  |  |
| cliphist |  community |  LTS /  testing+ |  |  |
| grim / slurp |  |  |  |  |
| flameshot |  |  |  |  |

## Display & Input

| Binary | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| swaybg |  |  |  |  |
| swayidle |  |  |  |  |
| swaylock |  |  |  |  |
| gammastep |  |  |  |  |
| brightnessctl |  |  |  |  |
| wlr-randr |  |  |  |  |

## Media & System

| Binary | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| playerctl |  |  |  |  |
| wireplumber |  |  |  |  |
| NetworkManager (nmcli) |  |  |  |  |
| bluez (bluetoothctl) |  |  |  |  |
| libnotify (notify-send) |  |  (`libnotify-bin`) |  |  |
| gnome-keyring |  |  |  |  |
| nautilus |  |  |  |  |
| xdotool |  |  |  |  |

## Utilities

| Binary | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| jq |  |  |  |  |
| crudini |  |  |  |  |
| libxml2 (`xmllint`) |  |  (`libxml2-utils`) |  |  (`libxml2-tools`) |
| inotify-tools |  |  |  |  |
| ImageMagick |  |  |  |  |
| grim / slurp |  |  |  |  |
| qt6ct |  |  |  |  |

## Fonts

| Font | Arch | Debian / Ubuntu | Fedora | openSUSE |
|---|---|---|---|---|
| Noto Sans / Mono |  `noto-fonts` |  `fonts-noto` |  `google-noto-sans-fonts` + mono |  `google-noto-sans-fonts` + mono |
| DejaVu Sans |  `ttf-dejavu` |  `fonts-dejavu-core` |  `dejavu-sans-fonts` |  `dejavu-fonts` |
| FiraCode Nerd Font |  AUR `ttf-firacode-nerd` |  `fonts-firacode` (unstable) |  COPR `fira-code-nerd-fonts` |  download |

## Summary: Build Requirements

### Must build (not packaged anywhere)

*(Currently, all core dependencies are packaged or provided natively via Zig.)*

### Package-managed on some distros, build on others

| Tool | Distros needing build |
|---|---|
| **sfwbar** | Debian/Ubuntu stable (not in repos) |
| **fuzzel** | Debian/Ubuntu stable (not in repos) |
| **FiraCode Nerd Font** | Fedora, openSUSE; all non-Arch distros for the Nerd variant |

### Distro build deps table

```sh
# Arch
sudo pacman -S base-devel gtk3 json-c

# Debian/Ubuntu — build deps
sudo apt install build-essential cmake libgtk-3-dev               # sfwbar from source

# Fedora — build deps
sudo dnf install gcc make pkg-config gtk3-devel json-c-devel

# openSUSE — build deps
sudo zypper install gcc make pkg-config gtk3-devel libjson-c-devel
```
