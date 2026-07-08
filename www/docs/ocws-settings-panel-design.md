# OCWS Settings Panel Design

## Philosophy
Inspired by DMS (DankMaterialShell) and Noctalia, but adapted for OCWS's C + sfwbar architecture. Uses GTK3 native widgets with OCWS CSS styling for glassmorphic appearance.

## Architecture
```
ocws-settings (GTK3 app)
├── Sidebar navigation (icon + label)
├── Content stack (scrollable cards)
└── Header bar (title + actions)
```

---

## Tabs & Features

### 1. Appearance (Theme Engine)
**DMS-inspired, adapted for INI themes**

| Feature | Widget | Description |
|---------|--------|-------------|
| Active Theme | Card + Grid | Show current theme name, color dots for quick switch |
| Theme Category | Button Group | Generic / Auto (matugen) / Custom / Browse |
| Color Palette | Color Grid | 10 theme colors (blue, purple, green, etc.) with live preview |
| Matugen Scheme | Dropdown | Tonal Spot, Vibrant, Content, etc. |
| Wallpaper Preview | Image Card | Show current wallpaper with color extraction |
| Custom Theme | File Picker | Load custom JSON theme file |
| Icon Theme | Dropdown | Papirus-Dark, Papirus-Light, etc. |
| Cursor Theme | Dropdown | Catppuccin-Mocha-Dark, etc. |
| Cursor Size | Slider | 16-48px |
| Font Scaling | Slider | 50-200% for UI elements |

### 2. Bar Configuration (DankBar-inspired)
**Multi-bar support with visual editor**

| Feature | Widget | Description |
|---------|--------|-------------|
| Bar List | Card List | Up to 4 bars with position/size info |
| Add/Delete Bar | Buttons | Create new bar configs |
| Position | Button Group | Top / Bottom / Left / Right |
| Display Assignment | Toggle List | Which monitors show this bar |
| Size | Slider | Bar thickness (24-64px) |
| Spacing | Slider | Edge spacing (0-32px) |
| Transparency | Slider | Bar opacity (0-100%) |
| Widget Transparency | Slider | Individual widget opacity |
| Corner Radius | Slider | Round corners (0-24px) |
| Square Corners | Toggle | Remove rounded corners |
| No Background | Toggle | Transparent bar background |
| Border | Toggle + Color | Add border around bar |
| Widget Outline | Toggle + Color | Outline around each widget |
| Auto-hide | Toggle + Delay | Hide when not hovering |
| Scroll Behavior | Dropdown | Workspace switching / Column scroll |
| Font Scale | Slider | Independent font scaling |
| Icon Scale | Slider | Independent icon scaling |

### 3. Widgets
**Widget enable/disable with drag reorder**

| Feature | Widget | Description |
|---------|--------|-------------|
| Widget List | Toggle List | All available widgets with enable/disable |
| Widget Presets | Button Group | Standard / Full / Minimal / Custom |
| Per-widget Settings | Expandable | Individual widget configuration |
| Widget Search | Search Bar | Filter widgets by name |

**Available Widgets:**
- Launcher, Workspaces, Clock, Volume, Battery, Network, Bluetooth, Tray, Dock, Media Player, System Monitor, Weather, Night Light, Power Profile, Quick Settings, Notification Center, Clipboard, Keybinds, Keyboard Layout, etc.

### 4. Workspaces
**Workspace behavior configuration**

| Feature | Widget | Description |
|---------|--------|-------------|
| Workspace Count | Slider | Number of workspaces (1-12) |
| Naming | Toggle | Show workspace names vs numbers |
| App Icons | Toggle | Show running app icons in workspace |
| Scroll Switching | Toggle | Switch workspace with scroll |
| Drag Reorder | Toggle | Drag to reorder workspaces |
| Follow Focus | Toggle | Bar shows focused workspace |
| Occupied Only | Toggle | Hide empty workspaces |
| Padding | Toggle | Pad workspace list to 3+ |

### 5. Keybinds
**Visual keybind editor**

| Feature | Widget | Description |
|---------|--------|-------------|
| Preset Selector | Dropdown | Default / Custom / Vim / Emacs |
| Keybind List | List View | All keybinds with search |
| Edit Keybind | Dialog | Modify key combination |
| Export/Import | Buttons | Save/load keybind configs |
| Reset | Button | Restore defaults |

### 6. Notifications
**Mako/Dunst configuration**

| Feature | Widget | Description |
|---------|--------|-------------|
| Daemon | Dropdown | Mako / Dunst / Disable |
| Position | Dropdown | Top-right, Top-center, etc. |
| Timeout | Slider | 1-30 seconds |
| Max Visible | Slider | 1-10 notifications |
| Font | Font Picker | Notification font |
| Border Radius | Slider | 0-24px |
| Background Color | Color Picker | Notification background |
| Text Color | Color Picker | Notification text |
| Border Color | Color Picker | Notification border |

### 7. Display
**Multi-monitor configuration**

| Feature | Widget | Description |
|---------|--------|-------------|
| Monitor List | Card List | All connected displays |
| Resolution | Info | Current resolution |
| Refresh Rate | Dropdown | Available refresh rates |
| Scale | Dropdown | 100%, 125%, 150%, 200% |
| Orientation | Dropdown | Normal, Left, Right, Inverted |
| Wallpaper | File Picker | Per-monitor wallpaper |

### 8. Audio
**Volume and device management**

| Feature | Widget | Description |
|---------|--------|-------------|
| Output Device | Dropdown | Available audio outputs |
| Input Device | Dropdown | Available audio inputs |
| Output Volume | Slider | 0-100% |
| Input Volume | Slider | 0-100% |
| Mute Toggle | Button | Mute/unmute |
| Now Playing | Card | Current media info + controls |

### 9. System
**Health, diagnostics, and maintenance**

| Feature | Widget | Description |
|---------|--------|-------------|
| Health Check | Button + Results | Run ocws-health, show results |
| Dependency Check | Button + Results | Run ocws-deps, show results |
| Validate Config | Button + Results | Run ocws-validate |
| System Info | Card | OS, kernel, compositor, shell version |
| Memory Usage | Progress Bar | Current memory usage |
| CPU Load | Progress Bar | Current CPU load |
| Disk Usage | Progress Bar | Disk space usage |

### 10. Persistence
**Backup, restore, and sync**

| Feature | Widget | Description |
|---------|--------|-------------|
| Backup | Button | Backup OCWS state + configs |
| Restore | Button + File Picker | Restore from backup |
| Git Sync | Button | Sync dotfiles with remote |
| Export Theme | Button | Export current theme to file |
| Import Theme | Button + File Picker | Import theme from file |
| Reset All | Button (danger) | Reset to factory defaults |

### 11. Plugins
**Plugin browser and management**

| Feature | Widget | Description |
|---------|--------|-------------|
| Installed Plugins | Toggle List | Enable/disable installed plugins |
| Plugin Browser | Button | Browse available plugins |
| Plugin Info | Card | Plugin description, version, author |
| Install Plugin | Button | Install from URL/file |
| Uninstall Plugin | Button (danger) | Remove plugin |

### 12. About
**System information**

| Feature | Widget | Description |
|---------|--------|-------------|
| OCWS Version | Info | Current version |
| Build Info | Info | C compiler, flags, date |
| Compositor | Info | labwc version |
| Bar Engine | Info | sfwbar version |
| Contributors | List | Project contributors |
| License | Info | MIT License |
| Links | Buttons | GitHub, Documentation, Report Issue |

---

## CSS Styling

### Glassmorphic Card Style
```css
.settings-card {
  background-color: rgba(30, 30, 46, 0.85);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 16px;
  padding: 16px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
}
```

### Toggle Switch Style
```css
switch {
  background-color: rgba(69, 71, 90, 0.8);
  border-radius: 12px;
  min-width: 48px;
  min-height: 24px;
}
switch:checked {
  background-color: #89b4fa;
}
```

### Slider Style
```css
scale trough {
  background-color: rgba(69, 71, 90, 0.6);
  border-radius: 4px;
  min-height: 6px;
}
scale slider {
  background-color: #cdd6f4;
  border-radius: 50%;
  min-width: 18px;
  min-height: 18px;
}
```

---

## Implementation Notes

### 1. Use OCWS KV Store for Settings
```c
// Read setting
char *value = ocws_kv_get("bar.transparency");

// Write setting
ocws_kv_set("bar.transparency", "0.85");

// Apply setting (shell command)
system("sfwbar-cmd bar-config topbar transparency 0.85");
```

### 2. Live Preview
- Theme changes: Apply immediately via `theme-engine.sh apply`
- Bar changes: Use `sfwbar-cmd` or IPC to update live
- Widget changes: Toggle widget visibility via CSS class

### 3. File Locations
```
~/.config/ocws/
├── user.config          # User overrides
├── plugins.config       # Plugin list
├── state/
│   ├── settings.json    # Settings panel state
│   └── backups/         # Backup files
```

### 4. Dependencies
- GTK3 (already required)
- json-c or cJSON (for JSON parsing)
- ocws-kv (existing binary)

---

## Comparison with DMS/Noctalia

| Feature | DMS | Noctalia | OCWS |
|---------|-----|----------|------|
| Theme Engine |  Matugen + JSON |  TOML palettes |  INI themes |
| Bar Config |  4 bars, drag reorder |  Single bar |  Up to 4 bars |
| Widget System |  QML plugins |  C++ widgets |  .widget files |
| Plugin Browser |  Registry |  Built-in |  Planned |
| Live Preview |  Instant |  Instant |  Instant |
| Multi-monitor |  Full |  Basic |  Full |
| Health Check |  |  |  Built-in |
| Backup/Restore |  |  |  Built-in |
| Keybind Editor |  Visual |  Config file |  Planned |
| Memory Usage | ~80MB | ~50MB | ~15MB |
