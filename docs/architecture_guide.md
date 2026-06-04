# PNGTuberPlus Architecture Guide

> Last updated: 2026-03-12 — Draggable point light gizmo for normal maps

## Overview

PNGTuberPlus is a Godot 4.4 desktop application for creating and performing with PNGTuber avatars. Users import sprite images (PNG, APNG, PSD), arrange them in a hierarchical layer tree, and the app responds to microphone input with bounce, wobble, blink, and eye-tracking animations.

The app has two primary modes:

- **View mode** — streaming/performing mode with mic input, bounce animation, costume switching
- **Edit mode** — sprite arrangement, property editing, save/load, PSD import

---

## Directory Structure

```
PNGTuberPlus/
├── main_scenes/           Main scene, edit controls, control panel
│   ├── main.tscn / main.gd       Entry point and orchestrator (~28 KB)
│   ├── EditControls.gd            Top menu bar (edit mode)
│   ├── ControlPanel.gd            Right-side streaming panel (view mode)
│   ├── Tutorial.gd                First-run tutorial overlay
│   ├── MicInputSelect.gd          Microphone dropdown
│   └── originLineDrawing.gd       Origin crosshair lines
│
├── ui_scenes/
│   ├── mouse/
│   │   └── mouse_cursor.gd       Click detection & tooltip in edit mode
│   ├── selectedSprite/
│   │   └── spriteObject.gd       Core sprite: rendering, physics, collision, outline
│   ├── spriteEditMenu/
│   │   ├── sprite_viewer.gd      Left sidebar — sprite property editor (265px)
│   │   └── chain.gd              Visual line during reparenting
│   ├── spriteList/
│   │   ├── viewer.gd             Right sidebar — layer tree + tabbed controls (310px, resizable)
│   │   ├── sidebar_tab_bar.gd    Reusable Details/Eye Tracking/Physics tab strip
│   │   ├── physics_tab.gd        Physics tab — wiggle controls
│   │   └── sprite_list_object.gd Individual list item with thumbnail
│   ├── psdImport/
│   │   ├── psd_import_dialog.gd     PSD layer selection dialog (import flow)
│   │   └── replace_review_dialog.gd Unified replace review dialog (PSD/folder/PNG)
│   ├── settings/
│   │   └── settings_menu.gd      Settings panel
│   ├── pushUpdates/
│   │   └── push_updates.gd       On-screen notification system
│   ├── light/
│   │   └── light_gizmo.gd        Draggable PointLight2D + edit-mode gizmo
│   └── volume/                    Audio level sliders & visualization
│
├── autoload/                      Global singletons (autoloaded)
│   ├── global.gd                  Central state: mic, selection, input, modes
│   ├── saving.gd                  JSON persistence, settings, save/load
│   ├── undo_manager.gd            Snapshot-based undo/redo (50-state history)
│   ├── psd_parser.gd              PSD file parser (background thread)
│   ├── apng_parser.gd             APNG/GIF detection and sprite sheet assembly
│   └── defaultAvatarData.gd       Built-in default avatar data
│
├── shader/
│   └── wobble.gdshader            Wave oscillation effect
│
├── effects/
│   └── wiggle/                    Wiggly-appendage physics (per-layer)
│       ├── wiggle_appendage.gd    Deformable textured mesh (Polygon2D) + verlet/angular-spring chain
│       └── wiggle_path_editor.gd  On-canvas ribbon-path tracer (Global.wigglePathMode)
│
├── ndi/                           NDI video output system
│   ├── ndi_output_manager.gd      SubViewport + Camera + NDIOutput orchestrator
│   └── ndi_ruler.gd               Draggable bottom crop line
│
├── addons/
│   ├── godot-ndi/                 NDI GDExtension plugin (optional)
│   ├── godot-streamdeck-addon/    Elgato Stream Deck integration
│   └── godot-git-plugin/          Git version control plugin
│
├── font/                          Custom fonts
├── bin/                           GDExtension binaries
├── docs/                          Documentation
└── project.godot                  Godot project configuration
```

---

## Autoload Singletons

Registered in `project.godot` under `[autoload]`:

| Singleton          | File                           | Purpose                                              |
|--------------------|--------------------------------|------------------------------------------------------|
| `Saving`           | `autoload/saving.gd`          | Avatar persistence (JSON + base64 images), settings  |
| `Global`           | `autoload/global.gd`          | Central state manager, mic input, selection, input    |
| `DefaultAvatarData`| `autoload/defaultAvatarData.gd`| Built-in default avatar data                        |
| `UndoManager`      | `autoload/undo_manager.gd`    | Snapshot-based undo/redo with image caching           |

Additional parsers (not autoloaded, instantiated on demand):
- `PSDParser` (`autoload/psd_parser.gd`) — threaded PSD file parsing
- `APNGParser` (`autoload/apng_parser.gd`) — APNG/GIF detection and sprite sheet assembly

---

## Main Scene Hierarchy

Entry point: `main_scenes/main.tscn` controlled by `main_scenes/main.gd`

Key child nodes:
- `OriginMotion/Origin` — root container for all sprites; bounces vertically on speech
- `Camera2D` — main viewport camera (zoom 10%-400%, middle-mouse pan)
- `EditControls` — top menu bar in edit mode
- `ControlPanel` — right-side streaming controls in view mode
- `SpriteViewer` — left sidebar sprite editor (child of EditControls)
- `SpriteList` — right sidebar layer tree
- `Lines` — origin crosshair drawing
- `PushUpdates` — floating notification system
- Various file dialog nodes

---

## Edit Mode UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Exit | Add | Duplicate | Import PSD | Replace | Save | …  │  ← EditControls (menu_bar_bg, 28px)
├──────────────┬──────────────────────────┬───────────────────┤
│              │                          │  [speak][blink]   │
│  Sprite      │                          │  [link][unlink]   │
│  Viewer      │      Canvas              │  [trash]          │
│  (left       │      (sprites rendered   │───────────────────│
│  sidebar,    │       here, click to     │  Layer list       │
│  265px)      │       select)            │  (scrollable)     │
│              │                          │───────────────────│
│  - 3D preview│                          │  Costume buttons  │
│  - Sliders   │                          │───────────────────│
│  - Properties│                          │ [Details|Eye|Phys]│  ← tab bar
│  - Dividers  │                          │  active tab body  │  (scrollable)
│              │                          │───────────────────│
│              │                          │  Visibility Toggle │
│              │                          │  (310px, resize)  │
└──────────────┴──────────────────────────┴───────────────────┘
```

> Updated: 2026-02-17 — Left sidebar restyled (pink sliders, muted labels, section dividers) to match right sidebar theme. Visibility Toggle control migrated from left sidebar (`sprite_viewer.gd`) to right sidebar (`viewer.gd`) below eye tracking section. UI styling conventions documented in `docs/ui_styling_guide.md`.

> Updated: 2026-05-29 — Right sidebar gained a tab strip beneath the costume row (`ui_scenes/spriteList/sidebar_tab_bar.gd`): **Details** (the four layer toggles — Clip linked / Static element / NDI reference / Ignore bounce — relocated here from the left sidebar `sprite_viewer.gd`), **Eye Tracking** (the existing eye section moved into the tab), and **Physics** (wiggle controls, built by `ui_scenes/spriteList/physics_tab.gd`). The active tab persists in `Saving.settings["rightSidebarTab"]`; tab content lives in a `ScrollContainer` that fills the space above a bottom-pinned Visibility Toggle, so it can expand upward if the layer list is detached later. Engine is now Godot 4.6.

> Updated: 2026-06-02 — **Eye tracking gained a Mode (Position / Rotation).** The Eye Tracking tab now has two dropdowns: **Mode** (`eyeTrackType`: 0 = Position, the original translate-toward-target; 1 = Rotation) and **Target** (`eyeTrackMode`: Cursor / Layer — the old "mode:" dropdown, just relabelled; field name kept for save compat). **Rotation** (behavior superseded 2026-06-03) is a **limited head-tilt that tracks the cursor's vertical position on whichever side it's on** — the side nearest the cursor lifts toward an upper cursor and drops toward a lower one. It's a **saddle**: `u = (cursor − artworkCenter).normalized()` (screen frame), `target = clamp(sgn · 2·maxRad · u.x·u.y, ±maxRad)`, smoothed by `lerp_angle`. So the tilt is **0 when the cursor is straight up/down or straight to a side**, peaks (`±eyeTrackDistance°`) at the **diagonals**, and **reverses across the artwork's center lines**. Referenced from the **artwork's visual center** (used-rect center → `dragOrigin.to_global`), NOT the layer origin, so the reversal lands on the artwork's **50% line** wherever the origin sits. **`eyeTrackDistance` = max tilt °** and **Invert** flips the lean (`sgn`, default `+1`). Default (no invert): cursor upper-left → top tilts right (left side lifts), upper-right → top left; lower mirrors. **The "Up side" dropdown was removed (2026-06-04):** the saddle is symmetric in X/Y, so rotating its input only flipped the product's sign (Top/Bottom identical, Left/Right identical, the two groups differing only by sign) — i.e. it did nothing Invert didn't, so it was dropped and Invert is the sole flip. (The `eyeTrackForward` field is retained in persistence at default 0 for save compat but is now unused.) Earlier Rotation attempts (full aim; proportional lean-away from "up") were superseded: full aim spun/flipped, and a single-axis lean ignored how high/low the cursor sat on a side. It **composes with** the mic-driven `rotationalDrag`, which smooths the mic rotation into its own `_micRot`; `spriteObject._process` then sets `sprite.rotation = _micRot + _eyeTrackRotation` (NOT `+=` into `sprite.rotation` — that fed the look-at back into rotationalDrag's smoothing and compounded into a runaway spin). The amount label/slider reads "tracking distance" (px) in Position and "max tilt" (°) in Rotation (`_update_eye_amount_label`); both modes use the slider. `eyeTrackType` persists alongside the other eyeTrack fields (main.gd save/load + duplicate, undo_manager snapshot/restore/add); defaults to 0 so old saves are unchanged. Note: a wiggle layer forces `sprite.rotation = 0`, so eye-track Rotation doesn't apply while wiggle is on (the mesh stands in).

> Updated: 2026-06-01 — **Physics tab Presets.** A **Presets** section (top of the tab) holds a wrapping `HFlowContainer` of chips: 2 built-in starting points (`_BUILTIN_PRESETS` — Fluffy / Stiff) plus the user's saved customs (faint-pink tint). Click a chip → `_on_preset_pressed` applies the `_PRESET_KEYS` "feel" bundle (stiffness/damping/springiness/shape-return/weight/reactivity/motion-intensity/wag*/max-bend/Bones — NOT coverage, path, or enable/children) to the held layer (undoable; live via the per-frame `configure`). **+ Save current as preset** reveals a `LineEdit` (Enter captures the current layer's feel as a named custom; total presets are capped at `_MAX_PRESETS` = 10 incl. built-ins — a new name past the cap is refused, overwriting an existing one is fine); **right-click** a custom chip removes it. Customs persist in `Saving.settings["wigglePresets"]` (written immediately via `Saving.write_settings`). Preset controls enable only with an active wiggle layer. (Also: the **Bones** slider is `wiggleSegments`, renamed from "resolution".)

---

## Click-to-Select Architecture

Selection in edit mode flows through these components:

1. **`mouse_cursor.gd`** — listens for left-click via `_unhandled_input`, sets `_click_pending`
2. **`_process()`** in mouse_cursor — when `_click_pending` is true, performs a direct physics space query using `PhysicsDirectSpaceState2D.intersect_point()` at the current mouse position
3. **`Global.select(areas)`** — receives the array of Area2D hits, resolves parent chain (3 levels up from Area2D to sprite root), handles cycling when clicking the same spot repeatedly, sets `Global.heldSprite`
4. **UI panels update** — SpriteViewer and SpriteList read `Global.heldSprite` each frame to show/hide controls. When `heldSprite` is null, the SpriteViewer disables all sliders/buttons and dims the panel to 35% opacity; all signal handlers also have null guards as a safety net. (Updated: 2026-02-16)

### Selection lifecycle

`Global.heldSprite` must be nulled before freeing sprites to avoid dangling references. Both `_on_clear_avatar_pressed()` and `_on_load_dialog_file_selected()` set `Global.heldSprite = null` before calling `origin.queue_free()`. The undo system's `_restore_full()` does the same. (Updated: 2026-02-16)

### Mouse filter configuration

Decorative `ColorRect` background panels must have `mouse_filter = MOUSE_FILTER_IGNORE` so they don't consume clicks before they reach `_unhandled_input`. This applies to:

- `EditControls.gd` — `menu_bar_bg` (full-width top bar)
- `sprite_viewer.gd` — `_bg` (left sidebar background)
- `viewer.gd` — `_bg` (right sidebar background)

Interactive controls (buttons, sliders, scroll containers) keep the default `MOUSE_FILTER_STOP` so they still receive input normally.

### Auto-scroll sprite list on selection

> Updated: 2026-02-16 — auto-scroll to selected layer

When a sprite is selected (canvas click, keyboard scroll, or any path through `spriteEdit.setImage()`), the sprite list automatically scrolls to bring the corresponding list item into view via `viewer.gd:scroll_to_selected()`, which calls `ScrollContainer.ensure_control_visible()`. This is a no-op when the item is already visible.

### Physics query vs cached overlap

The mouse cursor uses `PhysicsDirectSpaceState2D.intersect_point()` instead of `Area2D.get_overlapping_areas()` because the latter returns cached results from the previous physics step, creating a one-frame timing mismatch with the cursor position updated in `_process()`.

---

## Sprite Object (`spriteObject.gd`)

Each sprite layer is an instance with:

- **Rendering**: `Sprite2D` with texture, animation frames, offset
- **Physics**: `Area2D` with collision shape for click detection and outline drawing
- **Hierarchy**: `id`, `parentId`, `parentSprite` for parent-child tree
- **Animation**: frame count, animation speed, wobble (x/y frequency & amplitude)
- **Movement**: drag speed, rotational drag, rotation limits, stretch/squash
- **Visibility**: costume layers (10 slots), toggle key binding, speaking/blinking frames
- **Eye tracking**: enable flag, distance, speed, invert. In edit mode, tracking is suppressed only for the selected sprite (`Global.heldSprite`) so unselected sprites stay lively; in view mode tracking always runs. (Updated: 2026-02-16)

Sprites live under `OriginMotion/Origin` in the scene tree and use the `"saved"` group for enumeration.

> Updated: 2026-03-07 — Parenting & hierarchy hardening (14 bugs fixed)
> - `getAllDescendants()` added for recursive descendant collection (used by `setClip()`)
> - `unlinkChildren(parentSpr)` on `Global` unlinks direct children before parent delete, preserving grandchild chains
> - `linkSprite()` / `unlinkSprite()` zero all ancestor wobbles before position calculations to prevent wobble baking
> - `_skip_ready_reparent` flag on spriteObject skips `_ready()` timer-based reparent when duplicate handler reparents immediately
> - Sprite list uses DFS tree flattening for correct sibling ordering, chain-walk indent computation, collapse state preservation across rebuilds, and ancestor-chain visibility in filter
> - `updateData()` generation counter guards against stale coroutine results on rapid calls
> - Undo/redo handles missing parents (orphan fallback to origin) and circular reference checks

---

## Key Systems

### Undo/Redo (`undo_manager.gd`)

- Snapshot-based: captures full state of all sprites on each action
- 50-state history limit
- Snapshots store `Image` object references (not base64 PNG) — no encoding cost. PNG encoding only happens at file-save time. (Updated: 2026-02-16)
- Handles missing parent sprites by falling back to origin; detects circular references during restore (Updated: 2026-03-07)
- `save_state()` pushes snapshot; `save_state_continuous()` debounces within same frame

### Save/Load (`saving.gd`, `main.gd`)

- Format: JSON with base64-encoded PNG image data per sprite
- File extension: `.pngtp`
- PNG encoding for file saves runs on a background thread to avoid stalling the main loop (Updated: 2026-02-16)
- Settings stored separately: volume, sensitivity, window size, background color, costume key bindings, etc.
- Web build support via localStorage

### PSD Import (`psd_parser.gd`)

- Runs in background thread with progress reporting
- Supports RGB 8-bit PSD files (version 1, no PSB)
- Extracts layer names, bounds, opacity, channel data
- Import dialog lets user select which layers to add

### Unified Replace (`replace_review_dialog.gd`)

> Updated: 2026-02-28 — Added unified Replace flow

- Uses `DisplayServer.file_dialog_show()` with `FILE_DIALOG_MODE_OPEN_ANY` to select PSD, PNG, or folder
- **PSD replace**: Parses PSD (reuses PSD parser thread), matches layer names to existing sprite names (case-insensitive), shows review dialog
- **Folder replace**: Scans folder for PNGs, matches filenames to sprite names, shows review dialog
- **Single PNG replace**: If a sprite is selected, replaces that sprite directly (preserves APNG detection)
- Review dialog shows matched sprites (will be replaced), new items (checkboxes to optionally add), orphaned sprites (option to remove)
- Name matching: `psd://Name` → `Name`, `/path/file.png` → `file`, case-insensitive via `.to_lower()`
- `spriteObject.replaceSpriteFromData()` replaces image data in-place, preserving all properties (position, physics, costumes, parent-child, etc.)
- All operations are fully undoable via `UndoManager.save_state()`

### APNG/GIF Import (`apng_parser.gd`)

- Detects animated PNGs by checking for `acTL` chunk
- Composes frames into horizontal sprite sheet
- Calculates animation speed from frame delays
- Caps at max texture width (16384px)

---

## Input Handling

Key bindings (edit mode, handled in `global.gd`):

| Key        | Action                                    |
|------------|-------------------------------------------|
| Q / E      | Adjust Z-layer (front/back)               |
| O (tap)    | Snap origin to cursor                     |
| O (hold)   | Enter origin adjustment mode              |
| P          | Toggle reparent/link mode                 |
| Right-click | Cancel linking mode (when active)         |
| Z / Y      | Undo / Redo                               |
| Mouse wheel| Scroll through sprite list                |
| Ctrl+Scroll| Zoom viewport (10%-400%)                  |
| Middle drag| Pan viewport                              |
| Ctrl+K     | Tap: screenshot; Hold (≥1s): record transparent video. Format (WebM/APNG/GIF) and FPS (15/30/60) configurable in Settings. APNG/GIF default to 15 FPS, WebM defaults to 30 FPS. When NDI is enabled, captures the NDI crop view (auto-framed avatar) instead of the main camera view (updated 2026-03-12) |
| Left click | Select sprite / deselect on empty space   |

---

## Signals

Key signals defined in `global.gd`:

- `startSpeaking` / `stopSpeaking` — mic threshold crossed
- `pressedKey` — keyboard input forwarded for toggle bindings
- `fatfuckingballs` — sprite visibility toggle await trigger (legacy naming)

---

## Patterns and Conventions

- **Naming**: Mixed camelCase and snake_case throughout (not consistent)
- **Node references**: Stored on `Global` singleton (`Global.main`, `Global.spriteEdit`, `Global.spriteList`, `Global.mouse`)
- **State polling**: Most UI reads `Global.heldSprite` and other state every frame in `_process()` rather than using signals
- **ColorRect backgrounds**: Created programmatically in `_ready()`, must set `mouse_filter = MOUSE_FILTER_IGNORE` to avoid blocking canvas clicks

---

## NDI Video Output

> Updated: 2026-02-21 — initial NDI output system

### Overview

PNGTuberPlus can output an NDI video stream ("PixelLab Studio") that auto-frames the avatar with transparency. This enables direct capture in OBS and other NDI-compatible tools without green screen or window capture.

### Architecture

```
main (Node2D)
├── OriginMotion/Origin (sprites)
├── Camera2D (main viewport)
├── ... (existing nodes)
└── NDIManager (Node)              ← ndi/ndi_output_manager.gd
    └── SubViewport
        ├── Camera2D (NDI camera)
        └── NDIOutput (plugin node, name="PixelLab Studio")
```

The NDI SubViewport shares `world_2d` with the main viewport so the NDI camera sees the same sprites without duplicating nodes. The NDI camera independently positions and zooms to tightly frame the avatar.

### Key Files

| File | Purpose |
|------|---------|
| `ndi/ndi_output_manager.gd` | Orchestrator: creates SubViewport + Camera + NDIOutput, auto-framing logic, dirty flag |
| `ndi/ndi_ruler.gd` | Draggable horizontal crop line, draws dashed orange line in edit mode |

### Auto-Framing

1. Iterates visible sprites in `"saved"` group, computes union bounding box
2. Calculates bounce headroom: `bounceSlider^2 / (2 * bounceGravity)` + max wobble `yAmp` + 15% safety margin
3. Top = highest sprite edge - headroom; Bottom = ruler `crop_y`
4. Viewport sizing: user picks width preset (512/720/1080/1920), height computed from aspect ratio (auto mode) or user-set (manual mode)
5. Recalculation only when dirty flag set (avatar load, sprite change, settings change, costume change)

### NDI Ruler

A draggable horizontal dashed orange line visible in edit mode when NDI is enabled. Marks the avatar's bottom boundary for framing. Y offset stored in `Saving.settings["ndiRulerY"]`.

### Settings (`Saving.settings`)

- `ndiEnabled` (bool) — toggle NDI output
- `ndiWidth` (int) — output width preset
- `ndiMode` (string) — "auto" or "manual"
- `ndiManualWidth` / `ndiManualHeight` (int) — manual resolution
- `ndiRulerY` (float) — ruler Y offset from origin

### Graceful Degradation

Uses `ClassDB.class_exists("NDIOutput")` before instantiation. If the godot-ndi plugin is not installed, the NDI settings section shows "plugin not installed" and disables the toggle. The app never crashes from a missing plugin.

### Plugin Dependency

Requires the godot-ndi GDExtension plugin (by unvermuthet, MPL-2.0) in `addons/godot-ndi/`. Also requires NDI Runtime installed on the user's OS.

---

## Normal Map System

> Updated: 2026-03-12 — Normal map data pipeline (import, assign, save/load, undo/redo)

### Overview

Normal maps allow 2D lights (`Light2D`, `DirectionalLight2D`) to interact with sprite layers. A normal map is a **property of a diffuse layer**, never a separate layer in the list. Godot 4's `CanvasTexture` pairs a diffuse + normal texture on any Sprite2D.

### Data Model (`spriteObject.gd`)

Each sprite has optional normal map properties:
- `normalImageData: Image` — raw normal map Image
- `normalTex: ImageTexture` — texture for the normal map
- `normalPath: String` — file path or `"psd://layerName_NRML"`
- `loadedNormalImage: Image` — in-memory Image for PSD import (consumed in `_ready()`)
- `loadedNormalData: String` — base64 from save file (consumed in `_ready()`)

Key methods:
- `_rebuild_sprite_texture()` — if a normal map exists, wraps diffuse + normal in a `CanvasTexture`; otherwise assigns plain diffuse texture
- `setNormalMap(img, path)` — validates dimensions match diffuse, assigns normal, rebuilds texture
- `clearNormalMap()` — removes normal data, rebuilds texture
- `hasNormalMap() -> bool` — returns `normalTex != null`

### Naming Convention

Files/layers with the suffix `_NRML` (case insensitive) are treated as normal maps. Examples: `head_NRML.png`, `Body_nrml`.

### Auto-Pairing on Import

**PNG import** (`_import_png_files`): Separates `_NRML` files from diffuse files. Pairs by matching base name (e.g., `head.png` pairs with `head_NRML.png`). Unmatched normals attempt to pair with existing sprites; if no match, a toast notification is shown.

**PSD import** (`psd_import_dialog.gd`): `_NRML` layers are hidden from the layer selection UI but tracked in `normal_layers` dictionary. Count shown in dialog title. Passed through the `import_confirmed` signal and paired in `_finalize_psd_import()`.

### Save Format

Per-sprite dictionary additions:
- `normalPath` (String) — always saved
- `normalImageData` (String) — base64-encoded PNG, only if normal exists

Backward compatible: old saves without these fields load fine via `.has()` checks.

### Undo/Redo (`undo_manager.gd`)

- `_normal_cache: Dictionary` — sprite id → Image reference (mirrors `_image_cache` pattern)
- `invalidate_normal(sprite_id)` — call when normal map changes (import, clear)
- Snapshot includes `normalImageData` and `normalPath`; restore re-applies or clears as needed

### UI

- **Sprite Edit Panel** (`sprite_viewer.gd`): "normal map" section with status label, Import button (opens file dialog), Clear button
- **Sprite List** (`sprite_list_object.gd`): Blue "N" badge shown next to layer name when normal map is assigned

## Light Gizmo

> Updated: 2026-03-12 — Draggable PointLight2D for normal map visualization

### Overview

A single `PointLight2D` is always present in the scene so that normal-mapped sprites have a light to react to. The light lives inside `ui_scenes/light/light_gizmo.gd` (extends `Node2D`), added as a child of `origin` so it bounces with the avatar.

### Interaction

- **Edit mode**: yellow dot gizmo visible at the light position; click-drag within 20px to reposition
- **View mode**: gizmo hidden, light stays active
- Drag uses `_unhandled_input()` with `global_position` offset pattern; calls `get_viewport().set_input_as_handled()` to block sprite selection underneath
- `UndoManager.save_state()` called on drag start

### Properties

| Property | Type | Default | Maps to |
|----------|------|---------|---------|
| `light_energy` | float | 1.0 | `PointLight2D.energy` |
| `light_color` | Color | white | `PointLight2D.color` |
| `light_range` | float | 2.0 | `PointLight2D.texture_scale` |
| `light_enabled` | bool | true | `PointLight2D.enabled` |

### Integration

- **`main.gd`**: `_create_light_gizmo()` instantiates the gizmo and adds it to `origin`. Called in `_ready()` and after origin rebuild (load, undo full restore). `_apply_light_data(dict)` helper sets properties from a dictionary.
- **`swapMode()`**: calls `_light_gizmo.queue_redraw()` to show/hide gizmo dot
- **Save/Load**: `"_light"` key in avatar JSON with `{pos, energy, color, range, enabled}`. Old saves without `"_light"` get default values.
- **Undo**: snapshot includes `"_light"` sub-dictionary; `_restore()` and `_restore_full()` skip it in sprite loops and apply separately

## Wiggle (Physics)

> Updated: 2026-05-29 — Per-layer wiggly-appendage (tails, ears, antennae). Cleaned-up rewrite of PNGTuberRemix's `WigglyAppendage2D`: a textured `Line2D` ribbon driven by an angular-spring/verlet chain. (An earlier shader-UV-warp implementation was replaced because it clipped to the layer rect and the Mobile renderer broke its `MODULATE`/`NORMAL_TEXTURE` usage.)
>
> Updated: 2026-05-30 — **Ribbon path rewrite.** The appendage is no longer derived from the full texture bounds anchored at the layer origin (which displaced off-centre / canvas-sized layers). It is now driven by a user-traced **rest path** over the layer's content: the chain holds that (possibly curved) path as its rest shape and wiggles around it, and the content is **unwrapped along the path into a straight strip** (the bake) and re-wrapped via `Line2D` STRETCH — so at rest the ribbon reproduces the original artwork exactly, in place (rest-identity, verified straight + curved). `wiggleDirection` is removed (superseded by the path); a uniform **thickness** knob and per-point widths (taper-ready) were added. A new on-canvas **Ribbon Path Editor** (`Global.wigglePathMode`) lets the user trace/refine the path directly over the artwork.
>
> Updated: 2026-06-01 — **Renderer is now a deformable mesh, not a Line2D bake.** `WiggleAppendage2D extends Polygon2D`. The Line2D unwrap→strip→re-wrap sheared the artwork on **curved** rest shapes (a flat strip on a curve: outer edge longer than inner; verified — straight rest = exact, curved rest = sheared, independent of resolution). Replaced (Live2D ArtMesh / Spine path-mesh model, researched) with a 2-row triangle strip whose **per-vertex UVs map straight to the original layer texture**, so at rest each vertex sits at its own texture position with its own UV ⇒ the mesh **is** the artwork (identity, no distortion on any curve). The bake (`_bake_wiggle_strip` + helpers) is gone; `appendage.build_mesh(widths_along, uv_offset)` sets the UVs/triangulation from the rest pose (`uv_offset` = path root in tex px; **Polygon2D UVs are in pixels**), and `_update_mesh()` moves `polygon` each frame from the chain (Catmull-Rom-smoothed centerline ± perpendicular × width). Thickness/per-point widths now only set how much of the layer the band covers (no distortion). Normals carried by the same `CanvasTexture` (verified Polygon2D lights identically to Sprite2D under the app's `CanvasModulate`+`PointLight2D height=200`).

### Data flow

1. **`effects/wiggle/wiggle_appendage.gd`** (`WiggleAppendage2D extends Polygon2D`) — a decoupled port of the remix's angular-momentum spring chain: each joint is a torsional spring toward the previous joint's angle (+ curvature) with momentum, **linear damping**, a hard `max_angle` limit + `comeback_speed` spring, and gravity droop. The root point follows the node's `global_position` (so avatar bounce/drag/wobble propagate in as momentum → the whip), and `auto_wag` adds a **sinusoidal sway to the root direction** — the chain follows it with spring lag, so the base moves smoothly (clean sine) and the tip whips. Propagation smoothness is governed by `max_angular_momentum` (per-joint rotation-speed cap) and `stiffness_decay` (joints soften toward the tip), both scaled from stiffness in `_wiggle_params`. Output is a deformable triangle-strip mesh; `sample_local(t)` exposes the curve for child-follow. No anchor/mirror/`actor` coupling, and the original's brake-on-reversal damping was replaced with linear damping (it caused a rotate-stop-rotate stutter at wag reversals).
2. **`spriteObject._set_wiggle_active(on)`** — creates/frees the appendage under `DragOrigin` (sibling of the `Sprite2D`, so it shares the layer transform), then `_apply_wiggle_geometry()`; hides/shows the `Sprite2D`.
3. **`spriteObject._apply_wiggle_geometry()`** — the single geometry path. Catmull-Rom-smooths `wigglePath` (texture-px control points) into `_wiggleSmooth`, `_rebuild_wiggle_chain()` anchors the mesh at the path root and calls `appendage.set_geometry(rest_rel, resolution)` (the chain's rest = the path), then `appendage.build_mesh(_smooth_widths(_wiggleSmooth), _wiggleSmooth[0])` builds the mesh's per-vertex UVs (mapping to the real layer texture) + triangulation from the rest pose. The appendage's `texture` is the layer's own `CanvasTexture` (diffuse + normal). Re-run on path/width/thickness/image/resolution change (event-driven, not per-frame).
4. **`spriteObject._update_wiggle(delta)`** — each frame when `wiggleEnabled` (and not path-editing): holds the hidden sprite at identity (so linked children map cleanly), `configure()`s the chain from `_wiggle_params()`, and calls `appendage.tick(delta, tick)` (which moves the mesh). `talkBlink()` copies the sprite's `self_modulate`/`visibility_layer` onto the mesh so the talk/blink fade still applies.

> **Geometry/coords:** the rest path lives in **texture pixels**; `_tex_to_local`/`_local_to_tex` convert to the centered-`Sprite2D` `DragOrigin` space (`tex − size/2 + offset`). The chain holds the path as its rest shape and wiggles around it; the bake unwraps content **along** the path, so a tail anywhere in a canvas-sized layer wiggles **in place** (no displacement). `set_geometry` resamples to `resolution+1` equal-arc joints and stores per-joint rest relative angles. With no path, `_auto_fit_wiggle_path()` lays a straight 3-point path down the content's principal axis (so enabling wiggle / loading an old save is usable immediately).

> Updated: 2026-06-01 — **Origin move re-anchors the live mesh.** Moving the layer origin does `position -= d; offset += d` and compensates the `Sprite2D` via `sprite.offset` — but the mesh's anchor `_wiggleAppendage.position = _tex_to_local(path root)` also depends on `offset`, so without an update the active mesh slid by `d`. All three origin-move paths (`_input` drag, `moveOrigin`, `snapOriginToMouse`) now call **`_sync_wiggle_to_offset()`**, which re-sets only the anchor position (the rest vertices are offset-independent — the offset cancels in `_tex_to_local(p) − root` — so no rebuild/chain-reset needed, and the world anchor is unchanged so the chain doesn't react).

### Ribbon Path Editor (on-canvas)

`Global.wigglePathMode` (entered from the Physics tab's **✎ Edit ribbon path**, exited via the toggle / Esc / deselect) spawns a **`WigglePathEditor`** (`effects/wiggle/wiggle_path_editor.gd`) under the held layer's `DragOrigin`, so it inherits the content transform. It shows the static `Sprite2D` to trace over (ribbon hidden, full opacity, NDI layer 2) and draws the band (swept thickness), centerline spline, flow arrows, and root (diamond) / tip (ring) / mid (dot) handles in the theme accent, all at constant on-screen size via `get_global_transform_with_canvas()`. Direct manipulation in texture space: **drag** a position handle to move it, **drag** the amber square **width grip** (on a spoke out to the band edge at each point) to taper that point, **click** empty to add a point (split the nearest segment or extend an end, then drag), **right-click** a handle to remove it (min two). On press it grabs whichever of the position/width grip is closer. `mouse_cursor.gd` skips selection while the mode is on; the editor consumes its own input. On exit (or on releasing a grip) `apply_wiggle_path_changed()` re-bakes the now-visible ribbon.

### Children ride the bend

When `wiggleChildrenFollow` is on, `_apply_wiggle_to_children()` places each directly-linked child (`getAllLinkedSprites()`) at `appendage.sample_local(t)`, where `t` is the child's rest distance along the appendage; rotation follows the local chain tangent. The hidden sprite is held at identity so its local space matches the appendage's. Deeper descendants follow for free via the scene tree. Rest transforms are captured lazily and restored by `_release_wiggle_children()`.

### Parameters (`spriteObject.gd`)

User-facing units (degrees / friendly ranges), mapped to the chain in `_wiggle_params()`: `wiggleEnabled`, `wigglePath` (traced rest centerline, texture-px) + `wigglePathWidths` (per-point half-widths, the mesh band — auto-fit to the art's silhouette via `_fit_widths_to_content()`, which samples the rendered rest path and pools a conservative width envelope back to the control points) + `wiggleThickness` (UI label **coverage** — uniform multiplier over the band; 1.0 = silhouette fit, <1 trims, >1 pads; no distortion since the mesh maps art directly), `wiggleSegments` (UI label "Bones" — chain joints resampled from the path), `wiggleStiffness` (spring constant — also scales the rotation-speed cap + tip softening, so it doubles as the "snappy vs smooth propagation" knob), `wiggleDamping`, `wiggleBendFocus` (→ comeback_speed / "springiness"), `wiggleShapeReturn` (→ rest_return / "shape return" — an over-damped pull back to the rest shape, distinct from the spring: holds/returns the original shape without overshoot; 0 = free/floppy, 1 = rigidly holds rest), `wiggleWeight` (gravity droop), `wiggleMaxBend` (max angle/joint), `wiggleWagEnabled` / `wiggleWagAmount` (base-sway amplitude) / `wiggleWagSpeed` (auto-wag), `wiggleReactivity` (→ root-follow smoothness; higher = laggier whip), `wiggleChildrenFollow`. `segment_length` is derived from the path length; `subdivision` is fixed at 4. The **Ribbon** group in the Physics tab holds Edit-path / Auto-fit / coverage. **Auto-fit** (`_auto_fit_wiggle_path`) traces the artwork's **centerline (medial spine)** — `_trace_centerline()`: PCA for the main axis, start from an interior spine point, walk both ways re-centering on each perpendicular cross-section (so it follows curves), Douglas-Peucker to control points — then sizes the band to the silhouette; it adds as many points as the curve needs (a straight tail → 2-3, a curved one → ~8-12). Falls back to a straight principal-axis path if the content can't be traced. `_extend_ends()` then pushes each endpoint outward along its tangent by the opaque overhang there (`_content_reach`), so the band's flat end-cap reaches past a **pointed/rounded tip** instead of clipping it (a flat attachment with no overhang is left in place, so the wiggle root isn't shoved off the layer). `_orient_path_to_origin()` then flips the path so its **root** (index 0 = the wiggle pivot) is the endpoint nearest the **layer origin** (`size/2 − offset` in texture-px) — the trace's end order is otherwise arbitrary (PCA-axis sign), which can root a tail/ear at its tip; placing the origin near the base now picks the start. Normal point/width edits preserve the current `wigglePathWidths`; auto-width recalculation only runs from the explicit **Auto-fit to content** action or initial pathless setup. The amber width grips remain for manual per-point override / excluding part of a layer.

> Updated: 2026-06-01 — **Trace + width-fit hardening (both verified offscreen on a curved tapering tail).** (1) `_spine_walk` now terminates at tips: a normal step advances ~`trace_step`, so if re-centering snaps the point **> `trace_step * 3`** across a gap it means the walk stepped off a tip and `_spine_center` (which searches the whole image perpendicular) grabbed distant content — i.e. a **U-turn that re-traces the whole shape back to the other tip**. We break instead of following the jump. Before this, an arc traced ≈2× its length (out to one tip, U-turn, back to the other), and `smooth_path` of that doubled polyline looped — the band ballooned/looped at the base. (2) `_fit_widths_to_content` now measures coverage **perpendicular to the smoothed band centerline** (`smooth_path(wigglePath,10)`, nearest-point normal) rather than the raw control polyline, and marches with `_content_reach(..., threshold = 0.1)` (was 0.25) so the probe direction matches the band's real normal and reaches the anti-aliased silhouette edge, then grows the half-width `(ext + 2px) * 1.1` (~10%, 2026-06-01 — the bare fit still read slightly small). Fixes the earlier under-coverage ("too conservative"). `_content_reach` gained a `threshold` param (default 0.25 keeps the trace's centering behaviour).
>
> Updated: 2026-06-02 — **Coverage envelope fit.** `_fit_widths_to_content()` now measures silhouette reach at every sample of the same resampled/smoothed rest path the mesh renders (`_wiggle_mesh_rest_path()`), then pools each sample's required width back to the neighbouring control widths. This makes auto-fit conservative across curved segments and between sparse handles, avoiding the old case where a bulge between two control points clipped unless the user globally over-inflated **coverage**. The editor preview also no longer applies `wiggleThickness` twice, so the pink band matches the actual mesh coverage.
>
> Updated: 2026-06-02 — **Auto-fit-only width recalculation.** Moving/inserting/removing centerline points and dragging amber width grips now preserve the existing per-point widths. `_exit_path_edit()` no longer calls `_fit_widths_to_content()`; auto-width recalculation only happens from the explicit **Auto-fit to content** action (plus first-time pathless setup), so other handles do not jump while editing.

### Save/Load/Undo

All `wiggle*` fields persist alongside the eye-tracking fields (same sites in `main.gd` save dict + load, and `undo_manager.gd` snapshot / `_restore` / `_add_sprite_from_data`). `wigglePath` / `wigglePathWidths` are Packed arrays, serialized with `var_to_str` / `str_to_var` for the JSON save (raw `.duplicate()` in the in-memory undo snapshots); `wiggleThickness` is a scalar. All loaded behind `has()` guards, so old saves load with defaults (and `_auto_fit_wiggle_path()` gives any path-less wiggle layer a usable path on first activation). `_restore()` calls `setWiggle()` to rebuild/clear the ribbon for the restored state.
