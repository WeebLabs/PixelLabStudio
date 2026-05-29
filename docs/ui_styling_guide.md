# UI Styling Guide

> Created: 2026-02-17 — Left/right sidebar visual parity

Reference for all programmatic UI styling used across both sidebars. These overrides are applied in `_ready()` and take priority over any `.tres` theme files.

---

## Color Palette

### Backgrounds
| Role | Color | Usage |
|------|-------|-------|
| Panel background | `Color(0.15, 0.15, 0.15)` | Both sidebar `_bg` ColorRects |
| Divider | `Color(0.3, 0.3, 0.35)` | Section separator lines (1px) |

### Text Hierarchy
| Role | Color | Usage |
|------|-------|-------|
| Heading / bright text | `Color(0.85, 0.85, 0.9)` | `fileTitle`, toggle labels, active readouts |
| Body / muted text | `Color(0.75, 0.75, 0.8)` | All standard labels, checkbox text |
| Disabled text | `Color(0.35, 0.35, 0.4)` | Labels/buttons when no sprite selected |

### Accents
| Role | Color | Usage |
|------|-------|-------|
| Pink accent (enabled) | `Color(1.0, 0.7, 0.8)` | Slider fill, awaiting-input indicator |
| Pink accent (disabled) | `Color(0.55, 0.4, 0.45)` | Slider fill when no sprite selected |
| Danger hover | `Color(0.9, 0.45, 0.5)` | Delete "x" button hover state |

### Icon/Control States
| Role | Color | Usage |
|------|-------|-------|
| Dim (no sprite) | `Color(0.3, 0.3, 0.35)` | Icon sprite modulate when disabled |
| Normal | `Color(1, 1, 1)` | Icon sprite modulate when enabled |

---

## Typography

| Role | Font Size | Color |
|------|-----------|-------|
| Standard label | 12px | `Color(0.75, 0.75, 0.8)` |
| Heading label | 12px | `Color(0.85, 0.85, 0.9)` |
| Checkbox text | 12px | `Color(0.75, 0.75, 0.8)` |
| Flat button text | 12px | `Color(0.7, 0.7, 0.75)` normal, `Color(1, 1, 1)` hover |
| Delete button text | 11px | `Color(0.5, 0.5, 0.55)` normal, `Color(0.9, 0.45, 0.5)` hover |

---

## Slider Styling

Both sidebars share the same slider look:

### Enabled State
- **Fill** (`grabber_area`, `grabber_area_highlight`): `StyleBoxFlat`, `bg_color = Color(1.0, 0.7, 0.8)`
- **Track** (`slider`): `StyleBoxFlat`, `bg_color = Color(0.15, 0.15, 0.18)`
- **Grabber** (`grabber`, `grabber_highlight`): 16x16 white circle `ImageTexture` (radius ~6px)

### Disabled State
- **Fill**: `StyleBoxFlat`, `bg_color = Color(0.55, 0.4, 0.45)`
- **Grabber** (`grabber_disabled`): 16x16 gray circle `Color(0.45, 0.45, 0.48)`

### Grabber Circle Generation
```gdscript
var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
img.fill(Color(0, 0, 0, 0))
for px in range(16):
    for py in range(16):
        var dx = px - 8
        var dy = py - 8
        if dx * dx + dy * dy <= 36:  # radius ~6
            img.set_pixel(px, py, circle_color)
```

---

## Divider Conventions

- **Size**: `panel_width - 16` wide, 1px tall
- **Position**: x = 8 (8px margin from each edge)
- **Color**: `Color(0.3, 0.3, 0.35)`
- **Mouse filter**: `MOUSE_FILTER_IGNORE` (must not block clicks)
- Left sidebar: 5 dividers at fixed Y positions between sections
- Right sidebar: 4 dividers (controls/list, list/costume, costume/eye tracking, eye tracking/vis toggle)

---

## Button Patterns

### Flat Text Button (e.g., "Link", "Set Key")
```gdscript
btn.flat = true
btn.add_theme_font_size_override("font_size", 12)
btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
```

### Icon Button (e.g., speaking, blink, trash)
- `Sprite2D` with child `Button` (flat, 32x32 hit area)
- Scale: `Vector2(0.65, 0.65)`
- Modulate dimmed to `Color(0.3, 0.3, 0.35)` when no sprite

### Delete "x" Button
```gdscript
btn.flat = true
btn.add_theme_font_size_override("font_size", 11)
btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
btn.add_theme_color_override("font_hover_color", Color(0.9, 0.45, 0.5))
```

---

## Checkbox Styling

```gdscript
cb.add_theme_font_size_override("font_size", 12)
cb.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
```

---

## Tab Bar (sidebar tabs)

> Added: 2026-05-29 — `ui_scenes/spriteList/sidebar_tab_bar.gd` (`SidebarTabBar`)

Reusable tab strip used in the right sidebar (Details / Eye Tracking / Physics).
Rule-based layout: an `HBoxContainer` of flat buttons with `SIZE_EXPAND_FILL`
(equal widths), and a pink underline `ColorRect` placed under the active tab via
`index / count` so it reflows at any width.

- **Buttons**: `flat = true`, `focus_mode = FOCUS_NONE`, font size 12
  - Inactive `font_color`: `Color(0.7, 0.7, 0.75)`
  - Active `font_color` / hover: `Color(1, 1, 1)`
- **Underline**: 2px `ColorRect`, `Color(1.0, 0.7, 0.8)` (pink accent), `MOUSE_FILTER_IGNORE`
- **Bar height**: 26px (`SidebarTabBar.BAR_HEIGHT`)
- **Section headers inside a tab**: Label, font size 12, `Color(0.85, 0.85, 0.9)`

---

## Disabled State Patterns

When `Global.heldSprite == null`:
- Sliders: `editable = false`, fill swapped to muted pink, grabber swapped to gray
- Buttons: `disabled = true`
- Labels: color overridden to `Color(0.35, 0.35, 0.4)`
- Icon sprites: `modulate = Color(0.3, 0.3, 0.35)`
- Left sidebar sections: `modulate = Color(1, 1, 1, 0.35)` (35% opacity dim)
