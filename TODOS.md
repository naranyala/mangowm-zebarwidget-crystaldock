# Top Panel and Dock: Bugs & Enrichment Opportunities

## 🐛 Bugs / Issues Identified
1. **Dock Parabolic Zoom Blurriness**: The dock loads icons at `DOCK_ICON_SIZE` (default 28px) and caches them. When hovering, the icons are scaled up using `c.cairo_scale()`, causing the rasterized surfaces to look blurry and pixelated at larger sizes.
2. **Custom Command Shell Injection (`panel.zig`)**: `captureCmd` formats the shell string directly as `sh -c '{s}'`. If a widget's command contains a single quote (`'`), it breaks the shell command and throws an error (which was visible in the task output!).
3. **Dock Persistent Order Memory Leak/Limit**: Running apps that aren't pinned are dynamically added to the `items` array up to 100 entries. Over time or with too many windows, it could silently hit the hard limit without pruning correctly, or cause a crash if bounds are missed.
4. **Dock Drag and Drop Sorting Incompleteness**: `dock_mod.unpinAt` currently ignores some return values (fixed in earlier refactoring) but the underlying sort logic when dragging icons hasn't been perfected.

## ✨ Enrichment Opportunities
1. **Crisp High-Res Dock Zoom**: Instead of loading icons at 28px, force `icon.load(..., 128)` for dock icons. Cairo can cleanly downscale a 128px surface during the zoom animation, resulting in ultra-crisp dock icons no matter the magnification level.
2. **Active Window Pill Indicators**: Currently, the dock places simple grey/accent dots under app icons for multiple windows. We could enrich this by drawing a sleek "pill" (a widened rounded rectangle) for the currently focused window, inspired by modern docks.
3. **Smooth Spring Animations**: The dock magnification jumps instantly when the mouse enters/leaves the dock region. We can implement a simple exponential decay (lerp) or spring physics on the `hover_idx` and scale factor to make it feel buttery smooth.
4. **Interactive Hover States on Panel**: Panel widgets (like clock, volume, battery) lack visual feedback on hover. Adding a subtle semi-transparent pill background when the mouse hovers over them would improve interactivity.
5. **Pango-rendered Dock Tooltips**: The current dock tooltip uses primitive Cairo text plotting (`cairo_show_text`). We could switch it to use Pango layouts (like the panel widgets) to support rich fonts, emojis, and better text centering/shadows.

---

I recommend we start by developing half of these (e.g. the crisp dock zoom, the custom command shell injection fix, the active window pill indicators, and the panel hover states). 

How does this sound?

---

## Audit Findings (2026-07-19) — Panel & Dock Code

### Critical (Fixed)

- [x] **#20/#21 Config roundtrip data loss** — `session` and `versions` widgets silently dropped on config save because `widgetTypeToName` was missing entries. **Fixed**: added missing entries to `panel_config.zig`.
- [x] **#27 `surfacePreferredScale` missing modal_surface** — fallthrough assigned unknown surfaces to `launcher_surface`, corrupting scale state. **Fixed**: explicit `modal_surface` check added.
- [x] **#50 `applyPanelSurfaceHeight` always uses 560px** — session popup got unnecessary height. **Fixed**: per-popup type height calculation.
- [x] **#18 Hover feedback drawn twice** — redundant hover overlay in `renderPanel`. **Fixed**: removed duplicate block.
- [x] **#44 `launcherMeasure` hardcoded 150px** — ignores font scale. **Fixed**: uses `widgetTextWidth` with fallback.

### High (Open)

- [ ] **#1 `createWidget` uninitialized fields** — `undefined` init leaves `hidden`, `net_hist_*`, `net_retry_tick`, `key_fn` as garbage. Fix: use `std.mem.zeroes(Widget)`.
- [ ] **#3 `captureCmd` TOCTOU race** — temp file symlink attack vector. Fix: keep fd open, dup2 stdout.
- [ ] **#4 `ensureBuffer` stale `munmap`** — `munmap(null, old_size)` on first alloc failure. Fix: guard with null check.
- [ ] **#5 Dock `iconAt` per-frame rebuild** — O(n*m) on every mouse move. Fix: cache item list from last `draw()`.
- [ ] **#6 Volume wpctl parsing** — fallback parser misreads format. Fix: use command-specific parser.
- [ ] **#9 `wcUpdate` modifies global TZ** — thread-unsafe. Fix: use `localtime_r` with explicit timezone.
- [ ] **#10 Seat capability loss unhandled** — stale keyboard/pointer. Fix: destroy on capability drop.
- [ ] **#11 Net day rollover unsigned overflow** — panic on year boundary. Fix: bounds check before cast.
- [ ] **#12 Hardcoded `pinned_apps` overrides config** — race on startup. Fix: remove hardcoded defaults.
- [ ] **#49 Dock `draw` ignores `hover_idx`** — no visual feedback on hovered icon. Fix: draw highlight.

### Medium (Open)

- [ ] **#13 Hardcoded "foot-term"→"foot" hack** — compositor-specific. Fix: configurable alias map.
- [ ] **#14 `captureCmd` blocks main thread** — `system()` hangs if command hangs. Fix: fork/exec with pipes.
- [ ] **#15 `launcherDraw` hardcoded text** — not configurable. Fix: add label field to widget.
- [ ] **#16 Hardcoded terminal commands** — `foot btop`, etc. Fix: configurable per-widget.
- [ ] **#17 Workspace click always cycles** — can't select specific workspace. Fix: parse click x-position.
- [ ] **#22 Keyboard Escape uses hardcoded keycode 9** — not portable. Fix: document or add constant.
- [ ] **#23 `settings_gtk.c` index encoding `i*1000+dir`** — fragile for large indices. Fix: bit shift.
- [ ] **#24 Keymap fd not closed on mmap failure** — resource leak. Fix: close fd on failure.
- [ ] **#25 `modalClose` destroys/recreates surface** — wasteful. Fix: hide instead of destroy.
- [ ] **#28 `volScroll` always returns true** — consumes scroll even without pactl. Fix: return false on fail.

### Low (Open)

- [ ] **#29 Dead `launcher.zig`** — no-op, superseded by `app_launcher.zig`. Fix: remove.
- [ ] **#30 Dead `dock_view.zig`** — superseded by `drawDockTooltip` in `main_shell.zig`. Fix: remove.
- [ ] **#31 Dead `config.zig`** — superseded by `config_manager.zig`. Fix: remove.
- [ ] **#32 Dead `drawDynamicIsland`** — commented-out call. Fix: remove function.
- [ ] **#33 Dead `toggleLauncher`** — no-op, never called. Fix: remove function.
- [ ] **#34 Dead `configLoadWidgets`** — superseded by `pcfg.Config.load`. Fix: remove function.
- [ ] **#35 Widget struct ~2KB, 64 widgets = 128KB** — `old_widgets` copy in `reloadWidgets` also 128KB stack. Fix: heap allocate.
- [ ] **#36 `pinned_apps` naming** — suggests configurable but is const. Fix: rename to `DEFAULT_PINNED_APPS`.
- [ ] **#38 `gtk_menu_popup` deprecated** — GTK 3.22+. Fix: use `gtk_menu_popup_at_widget`.
- [ ] **#41 `netUpdate` bufPrintZ error** — skips `net_rx_prev` update, cascading failure. Fix: update before format.
- [ ] **#42 `settings_gtk.c` height hardcoded to 24** — ignores runtime changes. Fix: read from config.
- [ ] **#43 `g_autohide` missing `autohide_panel`** — GTK settings incomplete. Fix: add support.
- [ ] **#45 Icon sizes search order** — starts at 48px, not closest to requested. Fix: sort by distance.
- [ ] **#46 Battery click hardcodes `BAT0`** — fails on BAT1 systems. Fix: make configurable.
- [ ] **#47 Animation loop iterates all toplevels** — wasted when no hover. Fix: guard with flag.
- [ ] **#48 `wsMeasure` fallback 7px/char** — inaccurate for proportional fonts. Fix: use 8px or cache.
- [ ] **#51 Left widget positioning ignores settings_btn** — potential overlap. Fix: reserve width.
- [ ] **#52 Pins `%.*s` format truncates `usize`** — 64-bit. Fix: cast to `c_int`.
- [ ] **#53 `dock_c_impl.c` division by zero** — if surface width/height is 0. Fix: guard.
