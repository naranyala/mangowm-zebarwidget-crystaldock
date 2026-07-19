# Zigshell Cairo Pango - Feature Roadmap

This document outlines the planned modern features inspired by Material Design (DankMaterial/Noctalia).

## 1. Unified Quick Settings "Control Center"
- [x] Implement a drop-down surface overlay for the panel.
- [x] Add toggles (Wi-Fi, Bluetooth, DND) and sliders (Volume, Brightness).
- [x] Use Cairo drawing to create rounded pills and modern slider visuals.
- [ ] Add interactive Cairo-drawn sliders for Volume, Microphone, and Brightness.
- [ ] Add Media controls (Play/Pause, Next, Prev) with album art rendering.

## 2. Dynamic Theming Support & Glassmorphism
- [x] Consolidate color logic into a central `theme.zig` to apply Material You / Dankmaterial colors.
- [x] Make panel background transparent and rely on the compositor's blur.
- [ ] Build a JSON/Text parser to read color outputs from `matugen` or `pywal`.
- [ ] Dynamically update Cairo drawing colors (backgrounds, accents, text) on the fly without restarting.

## 3. Fluid Micro-Animations & Blur 
- [x] Create a 60fps frame loop that animates hover states on dock icons.
- [x] Linearly interpolate hover bounds for smooth growing/shrinking on dock icons.
- [ ] Configure `cairo` backgrounds to utilize compositor blur (e.g., `rgba` with 0.4 alpha) for a frosted glass effect.

## 4. Workspace Indicators (Pill Style)
- [ ] Implement the `ext-workspace-unstable-v1` (or `wlr-workspace-unstable-v1`) Wayland protocol.
- [ ] Render active workspaces as expanding, colored pills and inactive ones as subtle dots.
- [ ] Add click handlers to switch workspaces.

## 5. Integrated Notification Daemon
- [ ] Implement the `org.freedesktop.Notifications` D-Bus interface.
- [ ] Render incoming notifications as rounded popup surfaces.
- [ ] Maintain a "Notification History" list accessible from the Control Center.

## 6. OSD (On-Screen Display) Popups
- [ ] Create a centered, transient layer surface for volume/brightness changes.
- [ ] Draw large, animated progress bars and fade out automatically after a timeout.

## 7. Future Crystal-Dock Inspired Features
- [ ] **Application Pinning (Favorites)**: Read `.desktop` files from `/usr/share/applications` to populate the dock, keeping pinned apps visible when closed.
- [ ] **Multi-Window Indicators & Grouping**: Group `ToplevelInfo` items by `app_id` and draw multiple `cairo_arc` indicator dots below grouped icons.
- [ ] **Intellihide / Auto-Hide**: Dynamically slide the dock off-screen when maximized windows overlap using `cairo_translate` and `wlr_layer_surface_v1_set_exclusive_zone`.
- [ ] **Live Window Previews**: Utilize Wayland screencopy protocols to draw live thumbnail buffers when hovering over a dock icon.
- [ ] **Drag-and-Drop Reordering**: Track `WL_POINTER_BUTTON_STATE_PRESSED` and motion events to let users click, drag, and swap icon indices.
- [ ] **Parabolic Magnification (Mac Style)**: Apply Gaussian distance scaling to dock icons on hover instead of simple linear scaling.

## 8. Stability & Refactoring
- [ ] **Non-blocking Process Spawning**: Replace `c.system` in `spawn()` with a native, non-blocking asynchronous process spawning approach (e.g., `std.process.Child`) to prevent panel hangs on unbackgrounded commands.
- [ ] **Bounds-Checked String Handling**: Replace C-interop string functions (`sscanf`, `fgets` into fixed arrays) with Zig's native string formatting and bounds-checking slices to prevent silent truncations.
- [ ] **Safe Temp Files**: Ensure temporary files used in `ccUpdate` are cleaned up correctly even if the subprocess is killed or fails.

## 9. Code Quality & Maintenance
- [ ] **Extract Theme API**: Move hardcoded font sizes and `cairo` color codes into a `theme.zig` configuration struct, enabling customizable `.toml`/`.css` styles without recompilation.

## 10. Modern UX Enhancements
- [ ] **Scroll Wheel Integration**: Implement `.axis` and `.axis_discrete` Wayland events to pass scroll actions down to a new `.scroll_fn` on widgets (enables volume/brightness adjustment by scrolling).
- [ ] **StatusNotifierItem (System Tray)**: Implement an SNI host over D-Bus to embed modern app indicator icons into the panel.
- [ ] **Hover Tooltips**: Add a `.hover_fn` or `.tooltip_fn` to widgets for displaying extended information on pointer motion (e.g., full date on clock, IP on network).
- [ ] **Event-Driven Widget Updates**: Transition widgets (Media, Network, Volume) from polling loops to event-driven updates via DBus listeners (like `zbus`) to save CPU cycles.
