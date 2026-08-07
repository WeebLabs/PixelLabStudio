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
| Role | Color | Constant | Usage |
|------|-------|----------|-------|
| Heading / bright text | `Color(0.85, 0.85, 0.9)` | `SidebarUI.TEXT_HEADING` | `fileTitle`, toggle labels, active readouts, dialog titles |
| Body / muted text | `Color(0.75, 0.75, 0.8)` | `SidebarUI.TEXT_BODY` | All standard labels, checkbox text, menu bar buttons |
| Disabled text | `Color(0.35, 0.35, 0.4)` | `SidebarUI.TEXT_DISABLED` | Labels/buttons when no sprite selected |

> Updated: 2026-08-07 — The palette lives in `ui_scenes/common/sidebar_ui.gd` as
> named constants. Sidebars, the menu bar and dialogs all draw from them rather
> than repeating literals, so a palette change is one edit.

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

## Tab Bar

> Added: 2026-05-29 — `ui_scenes/spriteList/sidebar_tab_bar.gd` (`SidebarTabBar`)
> Updated: 2026-08-07 — Moved to `ui_scenes/common/tab_bar.gd` and renamed `AppTabBar`; the settings panel uses the same strip.

Reusable tab strip used in the right sidebar (Details / Tracking / Physics) and in the settings panel.
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

---

## Form Rows

> Added: 2026-08-07 — `ui_scenes/common/form_ui.gd` (`FormUI`)

Labelled control rows, used by the settings panel and available to any future
form. Panels declare what a setting is; the row decides where it sits.

- **Row**: `HBoxContainer`, 24px tall, 8px separation. Caption on the left at a fixed 118px so controls line up down the form; control fills the rest.
- **Section**: heading (12px, `SidebarUI.TEXT_HEADING`) + 1px `DEFAULT_DIVIDER_COLOR` hairline + a 8px-separated column of rows.
- **Caption**: 12px, `SidebarUI.TEXT_BODY`.
- **Slider row**: shared slider theme, plus a right-aligned 56px readout in `TEXT_HEADING`. Pass a `format` Callable for readouts like `Unlimited` or `1 in 200`.
- **Field** (`LineEdit`, and the hotkey bind buttons): `bg_color 0.1`, 3px corner radius, focus border `Color(0.45, 0.45, 0.5)`. Same look as the layer filter field.
- **Flat row button**: 12px, `Color(0.7, 0.7, 0.75)`, white on hover; `danger: true` hovers `Color(0.9, 0.45, 0.5)`.

---

## Modal Dialog

> Added: 2026-08-07 — `ui_scenes/common/modal_dialog.gd` (`ModalDialog`)

The one modal in the application: session recovery, save/load progress, import
progress, video encoding. Two near-identical builders with hand-placed children
and drifting colors were folded into it.

- **Scrim**: full-rect `ColorRect`, `Color(0, 0, 0, 0.35)`, `MOUSE_FILTER_STOP`. This is the modal guard, consuming clicks before they reach `mouse_cursor._unhandled_input`; no `canvas_input_blocker` Area2D is needed.
- **Panel**: `PanelContainer` in a `CenterContainer`, `StyleBoxFlat` with `bg_color = SidebarUI.DEFAULT_PANEL_COLOR`, 1px `SidebarUI.DEFAULT_DIVIDER_COLOR` border, 4px radius, 16px padding. Minimum width 360 (`set_panel_min_size` to widen).
- **Title** (also the live status line on progress dialogs): 14px, `SidebarUI.TEXT_HEADING`, centered
- **Message**: 12px, `SidebarUI.TEXT_BODY`, centered, word wrap
- **Progress bar**: 20px tall, track `Color(0.2, 0.2, 0.22)`, fill `SidebarUI.SLIDER_FILL_ENABLED` (pink accent), 3px radius, matching the menu bar's level meters
- **Actions**: centered `HBoxContainer`, default-theme buttons at 160x28. A `danger: true` action gets `Color(1.0, 0.6, 0.65)` on hover.
- `visibility_layer = 2`, so dialogs never appear in NDI output

**Sizing gotcha**, shared with the menu bar: anchors resolve once against the
parent's anchorable rect and do not follow the window here. Both components
therefore set their own `size` from the viewport and reconnect to
`Window.size_changed`. Do not switch either back to `PRESET_FULL_RECT`.

---

## Menu Bar (both modes)

> Added: 2026-08-07 — `ui_scenes/common/menu_bar.gd` (`AppMenuBar`)

The one top bar component. Edit mode and viewer mode both build from it, so bar
styling is defined here and nowhere else. Do not hand-style bar items at the
call site; add a factory to the component instead.

- **Bar**: 28px (`SidebarUI.MENU_BAR_HEIGHT`, shared with the sidebar chrome bounds), `Color(0.15, 0.15, 0.15)`, `MOUSE_FILTER_IGNORE` background
- **Zones**: left / center / right `HBoxContainer`s separated by `SIZE_EXPAND_FILL` spacers; 8px edge margin, 2px between items, 16px between groups

### Bar Button
```gdscript
btn.flat = true
btn.focus_mode = FOCUS_NONE
btn.add_theme_font_size_override("font_size", 14)
# StyleBoxEmpty with 6px left/right content margin on every state
```
| Role | Normal | Hover |
|------|--------|-------|
| Standard | `Color(0.75, 0.75, 0.8)` | `Color(1, 1, 1)` |
| Danger (Exit, Clear) | `Color(0.9, 0.45, 0.5)` | `Color(1.0, 0.6, 0.65)` |
| Disabled | `Color(0.35, 0.35, 0.4)` | same |

### Bar Icon Button
For items whose symbol reads faster than their name (the viewer bar's Settings
gear). Artwork must be a **white silhouette** on transparency: it is tinted with
the same tones as the text buttons, so icon and text items light up together.

```gdscript
button.icon = texture
button.expand_icon = true
button.tooltip_text = "Settings"          # required; an icon alone says nothing
button.custom_minimum_size = Vector2(ICON_SIZE + ITEM_PADDING * 2, ICON_SIZE)
button.texture_filter = TEXTURE_FILTER_LINEAR
```
- **ICON_SIZE**: 16px. Chosen so the 32px source art lands 1:1 at 2x scaling and stays crisp on Retina; the project default is nearest-neighbour, which frays a resampled glyph, hence the explicit linear filter.
- The button's own padding sits **outside** the icon, so it must be added back into the minimum width or the artwork is squeezed into what is left.
- `set_button_tone()` sets `icon_normal_color` / `icon_hover_color` alongside the font colours, so one call tones any bar item.

Separator: a `|` Label, font size 14, `Color(0.4, 0.4, 0.45)`.
Caption label (meter captions): font size 12, `Color(0.6, 0.6, 0.65)`.

### Level Meter
A live meter with a threshold marker riding on it: the bar shows the signal, the
disc shows where it triggers. Built by `add_level_meter()`.

- **Meter** (`ProgressBar`, `show_percentage = false`): 128x8, 3px corner radius. Track `Color(0.2, 0.2, 0.22)`; fill is per-control (mic Duration `Color(1.0, 0.7, 0.8)`, mic Level `Color(0.55, 0.78, 1.0)`)
- **Marker** (`HSlider` overlaid): `StyleBoxEmpty` for `slider` / `grabber_area` / `grabber_area_highlight` so only the grabber shows; 16px white disc from `SidebarUI.circle_texture`; `center_grabber = 1`, `grabber_offset = 0`; inset by the grabber radius at each end so the disc stops at the meter ends
- `scrollable = false` and a non-zero `step`, so the shared Ctrl+wheel nudge moves one step rather than the whole range

---

## Opacity + Blend Strip

> Added: 2026-06-04 — `ui_scenes/spriteList/blend_section.gd` (`BlendOpacitySection`)
> Updated: 2026-06-04 — Single-row Photoshop/Affinity layout (blend dropdown + opacity field with slider flyout).

Per-layer Blend + Opacity on **one row**, pinned to the bottom of the right sidebar's layer-list
region (above the draggable divider): `[ Blend dropdown … ]  [ 100% ▾ ]`.

- **Blend dropdown** (`OptionButton`): font size 12, `SIZE_EXPAND_FILL` (fills the row), `custom_minimum_size = (0, 22)`. Item id == `BlendMode.Mode` int.
- **Opacity field** (`LineEdit`): editable `NN%`, right-aligned, font size 12, `custom_minimum_size = (44, 22)`, `select_all_on_focus`. Dark rounded box (`bg_color 0.1`, corner radius 3, matching the filter field); focus border `Color(0.45, 0.45, 0.5)`. Accepts `0–100` with or without `%`.
- **▾ arrow** (`Button`, `flat`, `FOCUS_NONE`, font size 10, `(16, 22)`): opens a `PopupPanel` flyout holding a horizontal `HSlider` (shared fill/grabber styles, double-click-resettable to 1.0), right-aligned under the field.
- Disabled when no sprite: dropdown + arrow disabled, field shows `—`.
