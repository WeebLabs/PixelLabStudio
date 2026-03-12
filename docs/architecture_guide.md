# PNGTuberPlus Architecture Guide

> Last updated: 2026-02-21 — NDI video output system

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
│   │   ├── viewer.gd             Right sidebar — layer tree + controls (310px, resizable)
│   │   └── sprite_list_object.gd Individual list item with thumbnail
│   ├── psdImport/
│   │   ├── psd_import_dialog.gd     PSD layer selection dialog (import flow)
│   │   └── replace_review_dialog.gd Unified replace review dialog (PSD/folder/PNG)
│   ├── settings/
│   │   └── settings_menu.gd      Settings panel
│   ├── pushUpdates/
│   │   └── push_updates.gd       On-screen notification system
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
│  - Properties│                          │  Eye tracking     │
│  - Dividers  │                          │───────────────────│
│              │                          │  Visibility Toggle │
│              │                          │  (310px, resize)  │
└──────────────┴──────────────────────────┴───────────────────┘
```

> Updated: 2026-02-17 — Left sidebar restyled (pink sliders, muted labels, section dividers) to match right sidebar theme. Visibility Toggle control migrated from left sidebar (`sprite_viewer.gd`) to right sidebar (`viewer.gd`) below eye tracking section. UI styling conventions documented in `docs/ui_styling_guide.md`.

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
