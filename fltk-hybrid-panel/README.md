# FLTK Hybrid Panel for Wayland

An exploration project demonstrating how to build a **Wayland desktop panel** using a hybrid architecture:
- **Raw Wayland + wlr-layer-shell** for the panel surface (anchoring, exclusive zone, layer management)
- **FLTK** for offscreen widget rendering (text, shapes, meters)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Wayland Compositor (labwc)                │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  zwlr_layer_shell_v1 surface (top layer)              │  │
│  │  ├── Anchored: top + left + right (full-width)        │  │
│  │  ├── Exclusive zone: 32px (pushes windows down)       │  │
│  │  └── SHM buffer: ARGB8888 pixel data                  │  │
│  │       ↑                                               │  │
│  │       │ pixel copy                                    │  │
│  │       │                                               │  │
│  │  ┌────┴─────────────────────────────────────┐                 │  │
│  │  │  FLTK Fl_Image_Surface           │                 │  │
│  │  │  (offscreen rendering)           │                 │  │
│  │  │  ├── Clock widget                │                 │  │
│  │  │  ├── CPU usage meter             │                 │  │
│  │  │  ├── Memory usage meter          │                 │  │
│  │  │  └── Battery indicator           │                 │  │
│  │  └──────────────────────────────────┘                 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Why Hybrid?

FLTK 1.4 has excellent Wayland support for **standard application windows** (`xdg-shell`), but it does **not** support `wlr-layer-shell` — the protocol needed for desktop panels.

| Component | FLTK Native | This Project |
|---|---|---|
| Window management | `xdg-shell` (regular window) | `wlr-layer-shell` (panel) |
| Screen anchoring | ❌ Not supported | ✅ Top/bottom edge |
| Exclusive zone | ❌ Not supported | ✅ Reserves screen space |
| Widget rendering | ✅ Full toolkit | ✅ Via `Fl_Image_Surface` |
| Text/font rendering | ✅ Native | ✅ Via offscreen |

## Building

### Prerequisites

```bash
# Debian/Ubuntu
sudo apt install libwayland-dev wayland-protocols libcairo2-dev \
    libpango1.0-dev cmake ninja-build gcc g++ libxkbcommon-dev

# Fedora/OpenMandriva
sudo dnf install wayland-devel wayland-protocols-devel cairo-devel \
    pango-devel cmake ninja-build gcc gcc-c++ libxkbcommon-devel
```

### Build

```bash
# From the project root (labwc-fuzzel-sfwbar/)
cd sources/fltk-panel
cmake -B build -G Ninja
ninja -C build
```

### Run

```bash
# Must be run from a Wayland session (e.g., labwc, sway)
./build/fltk-panel

# Options
./build/fltk-panel --bottom          # Anchor to bottom
./build/fltk-panel --height 40       # Custom height
./build/fltk-panel --bottom --height 36
```

## Project Structure

```
sources/fltk-panel/
├── CMakeLists.txt          # Build system (links FLTK from ../fltk)
├── README.md               # This file
├── protocols/
│   └── wlr-layer-shell-unstable-v1.xml  # Layer-shell protocol definition
└── src/
    ├── main.cpp             # Entry point, argument parsing, event loop
    ├── wayland_panel.h/.cpp # Raw Wayland client + layer-shell surface
    ├── panel_widgets.h/.cpp # FLTK offscreen widget rendering
    └── system_info.h/.cpp   # Linux system info (CPU, memory, battery)
```

## Key Concepts

### 1. Layer Shell Protocol
The `zwlr_layer_shell_v1` protocol lets us create a surface that:
- **Anchors** to screen edges (top/bottom + left + right = full width)
- **Reserves space** via exclusive zone (other windows won't overlap)
- **Lives on a layer** (background, bottom, top, overlay)

### 2. SHM Buffers
We use Wayland shared memory (`wl_shm`) for pixel data:
- Create a shared memory file (`memfd_create`)
- Map it into our address space (`mmap`)
- Create a `wl_buffer` from it
- Write ARGB8888 pixels directly

### 3. FLTK Offscreen Rendering
FLTK's `Fl_Image_Surface` lets us render to an in-memory buffer:
- Create an offscreen surface of any size
- Use standard FLTK drawing calls (`fl_draw`, `fl_rectf`, `fl_font`, etc.)
- Extract the result as an `Fl_RGB_Image`
- Copy pixels to our Wayland SHM buffer

## Extending

### Adding a new widget
1. Add a `draw_xxx()` method to `PanelWidgets`
2. Create a draw data struct and a static draw function
3. Use `fltk_render_to_buffer()` to render it
4. Add it to the `render()` layout

### Adding more Wayland protocols
- **`wlr-foreign-toplevel-management`**: List open windows (taskbar)
- **`ext-workspace-unstable-v1`**: Workspace switcher
- **`wl_output`**: Multi-monitor support

## Compatibility

| Compositor | Layer Shell | Status |
|---|---|---|
| labwc | ✅ | Primary target |
| sway | ✅ | Compatible |
| Hyprland | ✅ | Compatible |
| GNOME (Mutter) | ❌ | Not supported |
| KDE (KWin) | ⚠️ | Partial (6.0+) |

## License

Exploration project — use freely.
