# Plan: SFwbar Unification — Replace Noctalia & Crystal-Dock

## Executive Summary

**Goal**: Deprecate `noctalia` and `crystal-dock` external shells by achieving full feature parity with our custom `sfwbar`-based OCWS. Retain multi-shell switcher as fallback during transition, but eventually phase out external dependencies.

**Current State**: Three shell modes exist:
- `crystal` — labwc + crystal-dock only
- `sfwbar` — labwc + sfwbar only (double panel)
- `both` — labwc + both sfwbar and crystal-dock (default)
- `noctalia` — labwc + noctalia shell

**Target State**: Single mode — `ocws` (labwc + sfwbar OCWS only)

---

## Phase 0: Keep Current Modes (NOW)

**Status**: Active — no changes to runtime behavior

All three modes remain functional. The shell switcher (`toggle-shell`) continues to work. This phase is about **planning only**.

---

## Phase 1: Feature Gap Analysis

### 1.1 What Crystal-Dock Provides

| Feature | Crystal-Dock | OCWS Current | Gap |
|---------|--------------|--------------|-----|
| Dock-style launcher |  Pinned app icons |  `dock.widget` + `dock-apps.widget` | Done |
| Magnification effect |  Mac-like zoom |  Not supported | **NEED** |
| Running app indicators |  Dot indicators |  Taskbar has focused state | Partial |
| Show desktop |  Click action |  `showdesktop.widget` | Done |
| Icon rendering |  High-res icons |  Taskbar icons | Done |

### 1.2 What Noctalia Provides

| Feature | Noctalia | OCWS Current | Gap |
|---------|----------|--------------|-----|
| Top bar |  Launcher, workspaces, clock, media, tray, system |  Same layout | Done |
| Control center |  Toggle panel with WiFi, BT, volume, brightness |  `ocws-control-center.widget` | Done |
| Notification daemon |  Built-in |  `ocws-notify` + `ocws-osd-notify` | Done |
| OSD popups |  Volume, brightness, etc. |  `ocws-osd-notify` | Done |
| Dock |  Optional bottom dock |  `dock.widget` | Done |
| Desktop widgets |  Clock, weather, etc. |  `desktop-*.widget` | Done |
| Lock screen |  Built-in blur |  `ocws-lock` (swaylock) | Done |
| Weather |  API integration |  `weather.widget` | Done |
| System monitor |  CPU, memory, disk graphs |  `ocws-sysmon` | Done |
| Wallpaper management |  Transitions, automation |  `ocws-wallpaper` | Done |
| Theme engine |  Builtin + community |  INI-based theme engine | Done |
| Animations |  CSS transitions | ️ Basic GTK3 transitions | Partial |
| Glassmorphism |  Blur, translucency | ️ CSS-only (no real blur) | Partial |

### 1.3 Critical Gaps to Close

**Must-have for parity:**
1. **Dock widget** — Pinned apps with magnification effect (Completed)
2. **Desktop widgets** — Floating clock, weather, system stats (Completed)
3. **Animation polish** — Smooth hover states, transitions
4. **Glassmorphism** — Real blur via gtk-layer-shell (if possible)

**Nice-to-have:**
- Live lyrics display
- AI assistant integration
- Advanced applets (crypto, GitHub notifications)

---

## Phase 2: Dock Widget Implementation (COMPLETED)

### 2.1 Requirements

- Pinned application launcher (configurable list)
- Mac-like magnification effect on hover
- Running application indicators (dot or glow)
- Auto-hide option
- Position: bottom (default), top, left, right

### 2.2 Technical Approach

**Option A: Pure sfwbar widget**
- Use `button` widgets with icon images
- CSS `transform: scale()` for magnification (GTK3 supports basic transforms)
- `Exec()` action for launching apps
- Draw running indicators via CSS pseudo-classes

**Option B: C plugin (recommended for magnification)**
- GTK layer shell surface
- Custom rendering for smooth magnification
- Better performance than CSS transforms

**Recommendation**: Start with Option A (sfwbar widget), migrate to Option B if performance is insufficient.

### 2.3 Implementation Steps

1. Create `dock.widget` with pinned app list
2. Add magnification CSS (scale on hover)
3. Add running app detection via `Exec("wmctrl -l")` or wlr-foreign-toplevel
4. Add auto-hide behavior
5. Test with 10+ pinned apps

---

## Phase 3: Desktop Widgets (COMPLETED)

### 3.1 Requirements

- Floating clock (large, centered)
- Weather widget
- System stats (CPU, memory, network)
- Sticky notes (optional)

### 3.2 Technical Approach

**GTK Layer Shell surfaces:**
- Each widget is a separate layer surface
- Position via `zwlr_layer_shell_v1`
- Transparent background
- Draggable (optional)

**sfwbar integration:**
- Widget files with `layer = "background"` or `layer = "overlay"`
- Configurable position and size

### 3.3 Implementation Steps

1. Create `desktop-clock.widget` (large clock, centered)
2. Create `desktop-weather.widget` (weather display)
3. Create `desktop-sysmon.widget` (system stats)
4. Add positioning config to `ocws.config`
5. Add toggle keybinding to show/hide desktop widgets

---

## Phase 4: Animation & Glassmorphism Polish

### 4.1 Animations

**Current**: Basic GTK3 transitions (`transition: all 0.2s ease-in-out`)

**Target**: Smooth, Noctalia-like animations
- Hover state transitions (scale, opacity)
- Popup open/close animations
- Workspace switch animations

**Approach**:
- Use GTK3 `transition` property (already in CSS)
- Add `transition-duration` and `transition-timing-function`
- Test on low-end hardware for performance

### 4.2 Glassmorphism

**Current**: CSS-only translucency (`rgba()` backgrounds)

**Target**: Real blur effect (like Noctalia)

**Approach**:
- `gtk-layer-shell` supports `blur` region
- sfwbar doesn't expose blur API directly
- **Option A**: Use `ocws-live-bg` for background blur
- **Option B**: Patch sfwbar to support blur (complex)
- **Option C**: Accept CSS-only translucency (simpler, less resource-intensive)

**Recommendation**: Option C (CSS-only) for now. Real blur is complex and may not be worth the effort.

---

## Phase 5: Mode Switcher Cleanup

### 5.1 Current Switcher Scripts

- `toggle-shell` — Simple switcher (crystal/sfwbar/both/noctalia)
- `shell-switcher.sh` — Complex switcher (double_panel/crystal_dock/noctalia)
- `labwc-shell-wrapper` — Legacy wrapper

### 5.2 Target Switcher

Single script: `ocws-shell` with modes:
- `ocws` — labwc + sfwbar OCWS (default, recommended)
- `legacy-crystal` — labwc + crystal-dock (deprecated)
- `legacy-noctalia` — labwc + noctalia (deprecated)

### 5.3 Implementation Steps

1. Create `scripts/ocws-shell` with mode selection
2. Update `dotfiles/labwc/autostart` to use `ocws-shell`
3. Deprecate `toggle-shell`, `shell-switcher.sh`, `labwc-shell-wrapper`
4. Remove crystal-dock and noctalia from optional dependencies

---

## Phase 6: Deprecation & Removal

### 6.1 Deprecation Timeline

| Month | Action |
|-------|--------|
| Month 1 | Dock widget implemented, desktop widgets beta |
| Month 2 | Animation polish, glassmorphism finalized |
| Month 3 | Mode switcher updated, deprecation warnings added |
| Month 4 | Remove crystal-dock from autostart |
| Month 5 | Remove noctalia from autostart |
| Month 6 | Remove legacy modes from switcher |

### 6.2 Removal Checklist

- [ ] Remove `dotfiles/crystal-dock/` directory
- [ ] Remove `dotfiles/noctalia/` directory
- [ ] Remove crystal-dock from `install-dependencies.sh`
- [ ] Remove noctalia from `install-dependencies.sh`
- [ ] Update `install.sh` to skip legacy configs
- [ ] Update `validate.sh` to check OCWS-only mode
- [ ] Update documentation to reflect single-mode architecture

---

## Phase 7: Testing & Validation

### 7.1 Feature Parity Tests

| Test | Crystal-Dock | Noctalia | OCWS |
|------|--------------|----------|------|
| Launch app from dock |  | N/A |  |
| Magnification effect |  | N/A | ️ |
| Running app indicator |  | N/A |  |
| Control center toggle | N/A |  |  |
| Notification display | N/A |  |  |
| OSD popup | N/A |  |  |
| Desktop widget | N/A |  |  |
| Animation smoothness |  |  | ️ |

### 7.2 Performance Benchmarks

| Metric | Crystal-Dock | Noctalia | OCWS Target |
|--------|--------------|----------|-------------|
| Memory usage | ~40MB | ~40MB | <30MB |
| Startup time | ~1s | ~1s | <0.5s |
| CPU usage (idle) | ~1% | ~1% | <1% |
| CPU usage (active) | ~5% | ~5% | <3% |

---

## Risk Mitigation

1. **Keep fallback modes** — Don't remove crystal-dock/noctalia until OCWS reaches parity
2. **Incremental rollout** — Implement one feature at a time, test thoroughly
3. **Performance monitoring** — Track memory/CPU usage during development
4. **User feedback** — Get community input before deprecating popular features
5. **Documentation** — Update README, TODOS.md, and user guides

---

## Success Criteria

- [x] Dock widget with magnification effect
- [x] Desktop widgets (clock, weather, sysmon)
- [ ] Animation polish matching Noctalia
- [ ] Single-mode switcher (`ocws-shell`)
- [ ] Crystal-dock and noctalia removed from autostart
- [ ] Performance benchmarks meet targets
- [ ] All existing features preserved

---

## References

- `TODOS.md` — Phase 1.5: SFWBar Unification
- `dotfiles/noctalia/config.toml` — Noctalia configuration reference
- `dotfiles/crystal-dock/panel_1.conf` — Crystal-Dock configuration reference
- `dotfiles/ocws/ocws.config` — Current OCWS configuration
- `shell/OCWS.md` — OCWS design philosophy (if exists)
