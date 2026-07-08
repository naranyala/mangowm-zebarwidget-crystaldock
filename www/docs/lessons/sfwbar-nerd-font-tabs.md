# Lesson: Nerd Font Glyphs In Labels Render As Tofu

## The Problem

Text widgets show Unicode replacement characters (tofu, like `□` or `▯`) where Nerd Font icons should appear:

```
Expected:  85%       75%       BT
Actual:   □ 85%      □ 75%      □ BT
```

Rendering is **silent** — no error message, no warning. The text is there, just invisible because the glyphs don't exist in the active font.

## Root Cause

sfwbar widgets use Nerd Font Unicode codepoints in their label `value` expressions:

```ini
# battery-text.widget
value = If(XBatLvl > 90, " ", ...

# brightness-text.widget
value = " " + Str(XBrightness, 0) + "%"

# bluetooth.widget
value = If(XBtState = "On", " BT", " BT Off")

# cpu-text.widget
value = " " + Str(XCpuLoad, 0) + "%"

# media-player.widget
value = If(XMediaStatus = "Playing", " ", ...
```

These codepoints (U+E000–U+FFFF range) are from the **Private Use Area** — only fonts specifically designed to include them (Nerd Fonts, Font Awesome, Material Design Icons) will render them.

The CSS either:
- Sets no `font-family` at all → GTK uses system default font (typically `sans-serif`), which lacks these glyphs
- Sets `font-family: 'Inter', 'Noto Sans', 'sans-serif'` → none of these include Nerd Font codepoints

## The Fix

Add `font-family` that includes a Nerd Font variant to every CSS rule for widgets that use icon glyphs:

```css
/* battery-text, cpu-text, memory-text, etc. — all text widgets with icons */
button.text_widget {
  font-family: "Noto Sans Nerd Font", "JetBrainsMono Nerd Font",
               "Symbols Nerd Font", sans-serif;
  ...
}
```

If you use a monospace Nerd Font for alignment:

```css
button.text_metric {
  font-family: "JetBrainsMono Nerd Font", "Noto Sans Mono Nerd Font", monospace;
  ...
}
```

## Where This Applies

Widgets using Nerd Font private-use-area codepoints in `value` expressions:

| Widget File | Glyph | Font Needed |
|-------------|-------|-------------|
| `battery-text.widget` |  (U+F039) | Nerd Font |
| `brightness-text.widget` |  (U+F0E0) | Nerd Font |
| `bluetooth.widget` |  /  (U+F0AF/U+F0B2) | Nerd Font |
| `cpu-text.widget` |  (U+F35B) | Nerd Font |
| `media-player.widget` |  (U+F388) | Nerd Font |

## Pattern To Remember

When you use a Nerd Font glyph in a label value, you must set `font-family` on that label to a font bundle that includes Nerd Font glyphs. The OS default sans-serif font never will.
