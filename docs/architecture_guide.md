# PNGTuberPlus Architecture Guide

> Last updated: 2026-08-06 — Phase 5 shared sidebar UI and input routing

## Overview

PNGTuberPlus is a Godot 4.6 desktop application for creating and performing with PNGTuber avatars. The supported and CI-pinned patch release is Godot 4.6.3. Users import sprite images (PNG, APNG, PSD), arrange them into a layered rig, and the app responds to microphone input with bounce, wobble, blink, and eye-tracking animations.

> Updated: 2026-08-06 — Godot 4.6 is the single engine baseline. `scripts/run_tests.sh` imports the project and runs the headless GDScript suite; `scripts/run_performance.sh` records repeatable CPU microbenchmarks under `.artifacts/`. CI runs the tests on macOS, Windows, and Linux using the official Godot 4.6.3 binaries. Native code must use the repository's pinned Godot 4.6 `godot-cpp` submodule revision. The duplicate top-level `godot-ndi/` package was removed; `addons/godot-ndi/` is the sole NDI integration. The obsolete bundled Git editor extension was also removed; source-control operations use the installed Git tooling and no longer add a native library to application/editor startup.

The app has two primary modes:

- **View mode** — streaming/performing mode with mic input, bounce animation, costume switching
- **Edit mode** — sprite arrangement, property editing, save/load, PSD import

---

## Directory Structure

```
PNGTuberPlus/
├── main_scenes/           Main scene, edit controls, control panel
│   ├── main.tscn / main.gd       Entry point and scene coordinator
│   ├── controllers/               Explicit main-scene lifecycle boundaries
│   │   ├── capture_controller.gd  Screenshot, recording, FFmpeg ownership
│   │   ├── save_controller.gd     Save dialogs, workers, session recovery
│   │   └── viewport_controller.gd Window, pan, zoom, edit/view layout
│   ├── EditControls.gd            Top menu bar (edit mode)
│   ├── ControlPanel.gd            Right-side streaming panel (view mode)
│   ├── Tutorial.gd                First-run tutorial overlay
│   ├── MicInputSelect.gd          Microphone dropdown
│   └── originLineDrawing.gd       Origin crosshair lines
│
├── ui_scenes/
│   ├── common/
│   │   └── sidebar_ui.gd         Shared styles, bounds, and chrome hit tests
│   ├── mouse/
│   │   └── mouse_cursor.gd       Click detection & tooltip in edit mode
│   ├── selectedSprite/
│   │   ├── spriteObject.gd       Core sprite runtime and scene integration
│   │   └── sprite_collision_builder.gd Alpha/fallback hitbox construction
│   ├── spriteEditMenu/
│   │   ├── sprite_viewer.gd      Left sidebar — sprite property editor (265px)
│   │   └── chain.gd              Visual line during reparenting
│   ├── spriteList/
│   │   ├── viewer.gd             Right sidebar — layer tree + tabbed controls (310px, resizable)
│   │   ├── sidebar_tab_bar.gd    Reusable Details/Tracking/Physics tab strip
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
│   ├── domain/sprite_state.gd     Canonical sprite property compatibility map
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
│   └── ndi_crop_box.gd            Resizable crop box (8 gizmos) defining the output frame
│
├── addons/
│   ├── godot-ndi/                 NDI GDExtension plugin (optional)
│   ├── godot-streamdeck-addon/    Elgato Stream Deck integration
│   └── psd-native/                Native PSD decode accelerator
│
├── font/                          Custom fonts
├── bin/                           GDExtension binaries
├── docs/
│   ├── architecture_guide.md      System map and data flows
│   ├── quality_baseline.md        Toolchain, tests, performance, dependency risks
│   └── refactor_plan.md           Phased execution and acceptance gates
├── tests/                         Headless unit, contract, smoke, and performance tests
├── scripts/                       Local quality-gate entry points
└── project.godot                  Godot project configuration
```

---

## Autoload Singletons

Registered in `project.godot` under `[autoload]`:

| Singleton          | File                           | Purpose                                              |
|--------------------|--------------------------------|------------------------------------------------------|
| `DefaultAvatarData`| `autoload/defaultAvatarData.gd`| Built-in default avatar data                         |
| `Saving`           | `autoload/saving.gd`          | Avatar persistence (JSON + base64 images), settings  |
| `Global`           | `autoload/global.gd`          | Central state manager, mic input, selection, input    |
| `UndoManager`      | `autoload/undo_manager.gd`    | Snapshot-based undo/redo with image caching           |

Additional parsers (not autoloaded, instantiated on demand):
- `PSDParser` (`autoload/psd_parser.gd`) — threaded PSD file parsing
- `APNGParser` (`autoload/apng_parser.gd`) — APNG/GIF detection and sprite sheet assembly

> Updated: 2026-08-06 — `Global` remains the compatibility-facing application
> state autoload, but runtime ownership is delegated under `autoload/runtime/`.
> `MicrophoneMonitor` owns exactly one tracked capture player, resolves the MIC
> spectrum analyzer by bus/type instead of numeric indexes, applies the level
> envelope and speaking transitions, validates device selection, and owns a
> generation-guarded delayed restart. It never frees unrelated autoload
> children and shuts down explicitly. `BlinkScheduler` owns deterministic blink
> timing and random-roll evaluation. `Global` mirrors their established public
> fields/signals so existing sprite/UI polling remains compatible. Toasts flow
> through `Global.notification_requested` rather than a retained UI-node
> pointer. `main.gd` attaches/detaches itself explicitly so scene-bound Global
> references and interaction modes are cleared during shutdown or scene swaps.
> Pure transition tests live in `tests/unit/test_runtime_services.gd`.

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

> Updated: 2026-08-06 — `main.gd` is the compatibility-facing scene
> coordinator and delegates three independent lifecycles under
> `main_scenes/controllers/`. `CaptureController` owns screenshots, recording
> viewports/files, FFmpeg discovery/arguments/progress, and deterministic
> cleanup. `ViewportController` owns resize settling, camera pan/zoom,
> selection-shadow following, window transparency, and edit/view layout.
> `AvatarSaveController` owns native save/load dialogs, manual and session-save
> threads, recovery selection, and save confirmation. Each controller receives
> `main`, `Global`, and `Saving` explicitly in `setup()` rather than resolving
> autoloads internally. Existing scene-signal method names remain as thin
> wrappers on `main.gd`. Pure format, zoom-boundary, recovery-policy, and image
> encoding contracts live in `tests/unit/test_main_controllers.gd`.

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

> Updated: 2026-06-04 — The **Eye Tracking** tab is renamed **Tracking**. Its enable checkbox is now scope-labelled by `refreshEyeUI()`: **"Enable (Layer)"** when a layer is selected (per-layer toggle), **"Enable (Global)"** otherwise (the global kill switch).

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

### Panel click-through guard

> Updated: 2026-06-12. Never select avatar elements behind a sidebar.

Because the sidebar/menu backgrounds use `MOUSE_FILTER_IGNORE` (above), a canvas click over a panel still reaches `mouse_cursor.gd` and runs the physics pick. `mouse_cursor.gd:_is_over_panel()` is the screen-space guard that rejects those clicks: the pick is applied via `Global.select()` only when `!_is_over_panel()`. Previously the guard also let the click through whenever an opaque sprite sat behind the panel, so clicking blank sidebar space (or the gaps between layer-list rows) could select the element behind it; it now blocks unconditionally while over a panel. Both sidebars are always present in edit mode (the left SpriteViewer dims to 35% but stays visible when nothing is selected; the right SpriteList tracks `editMode`) and selection runs only in edit mode, so the guard does not gate on per-panel visibility. Bounds use each panel's live `panel_width`, so they track sidebar resizing.

### Auto-scroll sprite list on selection

> Updated: 2026-02-16 — auto-scroll to selected layer

When a sprite is selected (canvas click, keyboard scroll, or any path through `spriteEdit.setImage()`), the sprite list automatically scrolls to bring the corresponding list item into view via `viewer.gd:scroll_to_selected()`, which calls `ScrollContainer.ensure_control_visible()`. This is a no-op when the item is already visible.

### Physics query vs cached overlap

The mouse cursor uses `PhysicsDirectSpaceState2D.intersect_point()` instead of `Area2D.get_overlapping_areas()` because the latter returns cached results from the previous physics step, creating a one-frame timing mismatch with the cursor position updated in `_process()`.

### Scroll wheel routing (cycle / zoom / slider nudge)

> Updated: 2026-06-12. Ctrl+scroll nudges the hovered sidebar slider; the viewport never zooms or cycles over a sidebar.

Three behaviors share the wheel, routed by cursor location:

- **Over the open viewport.** Plain scroll cycles sprite selection (`global.gd:scrollSprites()`, fed by a `_scroll_input` accumulator in `Global._input`); `Ctrl`+scroll zooms (`viewport_controller.gd`, polled).
- **Over a sidebar.** Neither of the above fires. `Global._input` intercepts the wheel first (it runs before GUI `_gui_input`): a `Range` (HSlider) under the cursor adjusts by one `step` and is consumed **only while `Ctrl` is held**. Without `Ctrl` the wheel is left alone so the enclosing scrollable section scrolls (the right sidebar's `ScrollContainer`, or the left sidebar's `position.y` scroll in `sprite_viewer._input`); sidebar sliders are created with `scrollable = false` so they do not self-adjust on that pass-through. Blank space and non-slider widgets behave the same. Either way it returns before the sprite-cycle accumulator.

Viewport zoom polls the `Input` singleton, so consuming the event cannot stop it; it is gated directly on `Global.isMouseOverSidebar()` instead. That helper delegates to `SidebarUI.is_over_editor_chrome()`, the canonical screen-space bounds check for the left/right sidebars and top menu bar. `mouse_cursor.gd` uses the same helper before sprite selection, so wheel routing and click-through blocking cannot drift apart. Screen-space bounds remain necessary because decorative backgrounds use `MOUSE_FILTER_IGNORE`, meaning `gui_get_hovered_control()` is null over blank panel areas. Sliders outside the sidebars (Settings, the volume/sensitivity sliders) keep their default wheel behavior.

> Updated: 2026-08-06 — `ui_scenes/common/sidebar_ui.gd` owns the
> click-through background/divider constructors, slider theme resources,
> enabled/disabled slider application, resize-edge geometry, safe panel-width
> clamp, and editor-chrome hit test shared by both sidebars. Every decorative
> `ColorRect` it creates explicitly uses `MOUSE_FILTER_IGNORE`. Component tests
> exercise style state, narrow-viewport clamps, resize margins, and open-canvas
> versus chrome routing in `tests/unit/test_ui_components.gd`.

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

> Updated: 2026-08-06 — Persistent sprite state is centralized in
> `autoload/domain/sprite_state.gd`. Its compatibility map is shared by manual
> saves, avatar loads, undo capture/restore, and duplication, including deep
> ownership rules for animation clips and wiggle arrays. New persistent
> properties must be added to this map and the save schema together. Duplicate
> and undo now retain NDI-reference, normal-map, clipping,
> static/ignore-bounce, stretch, toggle, blend, and physics state consistently.
> `sprite_collision_builder.gd` owns alpha polygon creation and fallback
> geometry. Animated fallback hitboxes use a single frame width (`sheet width /
> frame count`) and preserve rectangular frame dimensions. Tests live in
> `tests/unit/test_sprite_state.gd`. All sprite creation paths use one randomized,
> collision-checked ID allocator on `main.gd`; creating a fresh default-seeded
> generator per layer is no longer allowed.

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

> Updated: 2026-08-06 — `UndoManager` retains history, cache, hierarchy, and
> scene-reconciliation ownership, but delegates sprite property capture and
> application to `SpriteState`. Its former parallel save/restore maps were
> removed. Image caches still hold `Image` references rather than encoding PNGs.

### Save/Load (`saving.gd`, `main.gd`)

- Format: JSON with base64-encoded PNG image data per sprite
- File extension: `.pngtp`
- PNG encoding for file saves runs on a background thread to avoid stalling the main loop (Updated: 2026-02-16)
- Settings stored separately: volume, sensitivity, window size, background color, costume key bindings, etc.
- Web build support via localStorage

> Updated: 2026-08-06 — Persistence boundaries are versioned and validated before live scene state is changed. `autoload/persistence/avatar_save_schema.gd` migrates legacy unversioned avatars, supplies typed compatibility defaults, rejects unsupported future versions, duplicate IDs, invalid layers, and hierarchy cycles, and selects sprite entries by their validated shape rather than a fixed metadata allowlist. `settings_schema.gd` owns the complete canonical settings defaults and typed/ranged migration (including legacy NDI ruler-to-crop conversion). `value_codec.gd` is the only persistence-boundary parser for legacy Variant strings. `json_file_store.gd` bounds reads, reports JSON line errors, writes through a same-directory temporary file, and retains/reloads a previous complete `.bak` if replacement is interrupted. Manual saves only update `lastAvatar` after the avatar write succeeds; failed session saves re-arm the dirty flag. The `Saving` singleton remains the compatibility-facing API and exposes `last_error` plus `persistence_error` for actionable UI reporting.

Schema metadata uses `_schemaVersion`; underscore-prefixed root keys are reserved
for avatar-level metadata. A root entry is treated as a layer only when it is a
validated dictionary with `type == "sprite"`. Current schema migration and
atomic round-trip/recovery cases are fixture-tested in
`tests/unit/test_persistence.gd`.

> Updated: 2026-08-06 — Save execution is coordinated by
> `main_scenes/controllers/save_controller.gd`. It serializes the scene snapshot
> supplied by `main.gd`, owns both worker threads, joins them on shutdown, and
> keeps manual-save and recovery-copy writes mutually exclusive. The controller
> also owns the native file dialogs and the timestamp policy deciding whether a
> newer `user://session.pngtp` should be offered for recovery.

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
| Mouse wheel| Cycle sprite selection (only while the cursor is over the open viewport) |
| Ctrl+Scroll| Over the viewport: zoom (10%-400%). Over a sidebar: nudge the hovered slider/spinbox by one `step`. Sliders never adjust without Ctrl, and the viewport never zooms while the cursor is over a sidebar |
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

PNGTuberPlus can output an NDI video stream ("PixelLab Studio") framing the avatar with transparency. This enables direct capture in OBS and other NDI-compatible tools without green screen or window capture. The frame is the user-drawn crop box (see below); there is no automatic content framing.

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

> Updated: 2026-06-14 — Main-window transparency is coordinated by `main.gd:updateWindowTransparency()`: when NDI is active in view mode, the main viewport renders opaque while the NDI SubViewport keeps alpha; otherwise the main viewport becomes transparent only in view mode with a transparent background color. On Windows, `Window.transparent` is not toggled at runtime because flipping the native transparent-window flag after startup can leave the viewport backed by black when NDI is disabled again; the project setting creates the window transparent at boot, and viewport alpha/clear color controls the visible result.

> Updated: 2026-06-14. **Windows transparency needs the D3D12 RenderingDevice driver.** The per-pixel transparent window rendered opaque BLACK on Windows while working on macOS. Root cause: `rendering_device/driver="metal"` (project.godot) is the generic key with no `.windows` override, so Windows fell back to **Vulkan**, whose Windows swapchain present path does not honor per-pixel alpha (so `Color(0,0,0,0)` composites as opaque black). macOS uses Metal, which composites alpha natively. The flag/`transparent_bg`/clear-color all sit ABOVE the swapchain compositeAlpha layer, so no GDScript change can fix it. Fix: set `rendering_device/driver.windows="d3d12"` (DRIVER only; `rendering_method` stays `"mobile"`), so the BackBufferCopy screen-reading blend modes (`effects/blend/`, `hint_screen_texture`) and CanvasTexture normal maps are unaffected. This is the maintainer-recommended migration (godot PR #113213; symptom-match issue #111513). Verified working on Windows 2026-06-14.
>
> **BUILD REQUIREMENT (Windows releases, per build machine):** because `driver.windows="d3d12"`, a Windows export must ship the DirectX **Agility SDK `D3D12Core.dll`** (version >= `rendering/rendering_device/d3d12/agility_sdk_version`, currently **618**). With `application/export_d3d12=1` (set in `export_presets.cfg`), Godot's Windows exporter auto-bundles it: it copies **`D3D12Core.<arch>.dll`** from the **export-templates folder** (`<editor data>/export_templates/4.6.1.stable/`) into `<export>/<arch>/D3D12Core.dll` (with `application/d3d12_agility_sdk_multiarch=true`), which is exactly where the runtime looks (`.\<arch>\`, `arch`=`x86_64`). It is NOT an editor setting. **One-time per build machine:** drop `D3D12Core.x86_64.dll` (the Agility SDK's `build/native/bin/x64/D3D12Core.dll` from the `Microsoft.Direct3D.D3D12` NuGet, renamed) into that templates folder; then both editor-GUI and headless CLI exports bundle it automatically, no post-export step. (Optional debug extras `d3d12SDKLayers.<arch>.dll` / `WinPixEventRuntime.<arch>.dll` are not needed for release.) If a machine's templates folder lacks the DLL, the export silently omits it and `fallback_to_vulkan=true` degrades the build to Vulkan (transparency black again) rather than crashing (#104988). This machine is already set up; a backup copy is at `~/godot-agility-sdk/D3D12Core.dll`.

### Key Files

| File | Purpose |
|------|---------|
| `ndi/ndi_output_manager.gd` | Orchestrator: creates SubViewport + Camera + NDIOutput, crop-box framing, dirty flag |
| `ndi/ndi_crop_box.gd` | Resizable dashed-orange crop box with 8 gizmos, drawn in edit mode |

### Framing (manual crop box)

> Updated: 2026-06-12 — **The auto-framing is gone.** The old system computed a union bounding box of per-sprite envelopes (texture opaque rects grown by wobble/rotation/eye-track/wiggle margins) above a draggable horizontal crop line. Estimating every motion system's reach (wiggle chains, drag lag, rotational drag, animation clips...) proved impractical — margins were always too tight somewhere and too generous elsewhere — so the user now draws the frame directly. `_compute_sprite_envelope()`, `_get_opaque_rect_local()`, `_rotation_expanded_aabb()`, `_get_rest_position()`, `spriteObject.wiggle_bounds_local()`, and `ndi/ndi_ruler.gd` were removed.

1. The frame is the user-drawn **crop box**: origin-relative edges `[left, top, right, bottom]` in `Saving.settings["ndiCropRect"]`, placed at the avatar's **rest** position (`rest_origin_pos` = `origin.global_position − OriginMotion bounce offset`). The camera is static between recalcs, so the avatar visibly bounces *within* a fixed frame.
2. **One-to-one with the output (2026-06-13).** The rendered rectangle equals the drawn box exactly on all four edges. The earlier per-edge bounce/wobble headroom on the bottom (`bottom_margin = ref_y_amp + ref_eye + peak_displacement`) was removed: the crop now ships pre-configured per avatar, so it's WYSIWYG and whoever sets it up bakes any desired margin into the box itself (same as the top and sides). Consequence: an up-bounce can bring content below the box's bottom edge into the bottom of the frame, so a bouncing avatar's box should leave a little bottom headroom. This made the `ndiRefLayer` flag, the Neck/Body auto-detect, and the `peak_displacement` math **inert for framing** (the flag/UI/persistence still exist; pending a decision to remove them).
3. Viewport sizing: user picks width preset (512/720/1080/1920), height computed from the box's aspect ratio (auto mode) or user-set with letterbox fit (manual mode). Camera centered on the box.
4. Recalculation only when dirty flag set (avatar load, box edit, settings change; debounced 1 s). The edit-mode box (`ndi_crop_box.gd`) also anchors to `rest_origin_pos` so the on-canvas rectangle matches the output 1:1 even while the avatar bounces (it previously rode the live origin).

### NDI Crop Box

A dashed orange rectangle (`ndi/ndi_crop_box.gd`, spawned by the manager onto `Global.main`, visibility layer 2) visible in edit mode when NDI is enabled — same look as the old crop line. Resize via 8 constant-screen-size gizmos: 4 edge midpoints (move that edge, H/V resize cursors) and 4 corners (move both adjacent edges, diagonal cursors). Grabbing a **bare edge line** (away from any gizmo) returns `H_MOVE` and translates the whole box without resizing (move cursor), so you can reposition the frame by dragging any side. Minimum box size 64 px; sidebars block grabs (same screen-space guard as before). While dragging, bounce/wobble freeze at worst-case-down via `ndi_manager.crop_dragging` (checked in `main._process` and `spriteObject.wobble`).

> Per-avatar persistence (kept from the crop line, 2026-06-12): `_build_avatar_save_data()` writes `"_ndiCropRect"` ([l, t, r, b]) to the avatar JSON (alongside `"_light"` / `"_eyeTrackingGloballyEnabled"`), plus legacy `"_ndiRulerY"` (= box bottom) so older builds still pre-frame. `_on_load_dialog_file_selected()` restores `_ndiCropRect`; a legacy save with only `_ndiRulerY` keeps the current box and snaps its bottom to the line. Saves with neither key keep the current crop. Settings migration: `_load_settings()` seeds `ndiCropRect` from an old `ndiRulerY` (line Y becomes box bottom). Box edits are intentionally non-undoable (not in UndoManager snapshots).

### Settings (`Saving.settings`)

- `ndiEnabled` (bool) — toggle NDI output
- `ndiWidth` (int) — output width preset
- `ndiMode` (string) — "auto" or "manual"
- `ndiManualWidth` / `ndiManualHeight` (int) — manual resolution
- `ndiCropRect` (Array [l, t, r, b]) — crop box edges, origin-relative (replaced `ndiRulerY`, 2026-06-12)

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

## Blend Modes & Opacity

> Added: 2026-06-04 — Per-layer blend mode + opacity compositing.

Each sprite layer has `blendMode` (a `BlendMode.Mode` int) and `opacity` (0–1). The controls live
in a strip pinned to the **bottom of the right sidebar's layer-list region** (above the draggable
divider, mirroring the filter field that caps the top) — `ui_scenes/spriteList/blend_section.gd`
(`class_name BlendOpacitySection`), built/positioned/synced by `viewer.gd`.

### Modules (`effects/blend/`)
- `blend_mode.gd` (`class_name BlendMode`) — the mode enum (persisted as int, **append-only — never
  reorder**), display names, and render-tier categorization helpers.
- `blend_modes.gdshader` — one `canvas_item` shader holding every screen-reading blend formula,
  selected by a `blend_mode` uniform (if-chain on a uniform → effectively free).

### Three render tiers — only modes that need it pay any cost
| Tier | Modes | Mechanism | Backbuffer |
|------|-------|-----------|------------|
| Native default | Normal | `CanvasItemMaterial`, `PREMULT_ALPHA` | no |
| Native hardware | Add, Subtract | `CanvasItemMaterial` `BLEND_MODE_ADD`/`SUB` (correct under premultiplied alpha) | no |
| Shader | Multiply, Screen, Overlay, Darken, Lighten, Color Dodge, Color Burn, Hard Light, Soft Light, Difference, Exclusion | `ShaderMaterial` + `BackBufferCopy` | yes |

`spriteObject.applyBlendMode()` is the single path that assigns the material and creates/removes the
per-layer `BackBufferCopy`. The copy is the **first child of `DragOrigin`** at the layer's absolute z
(`z_as_relative=false`, `z_index=z`, kept in sync by `setZIndex()`), so its `COPY_MODE_VIEWPORT`
snapshot contains exactly the layers drawn **below** this one. The wiggle ribbon shares
`sprite.material`, so `applyBlendMode()` re-points it too.

### Premultiplied-alpha compositing (the shader)
Layer textures **and** the backbuffer are premultiplied (verified empirically on Mobile + Metal). The
shader un-premultiplies source and backdrop, applies the W3C separable blend, then outputs a
**premultiplied** result via `render_mode blend_premul_alpha` — so compositing stays correct over any
backdrop alpha (opaque editor window AND a transparent NDI/stream viewport). Opacity is folded into
`talkBlink()`'s gray `self_modulate` (`Color(o,o,o,o)`, `o = talk/blink × opacity`); the shader reads
it as `COLOR.a` and ignores `COLOR.rgb`.

### Save / Load / Undo
- **Save**: `blendMode` + `opacity` per sprite (`main.gd _build_avatar_save_data`); load + duplicate
  apply them with `.has()` guards. Missing fields default to Normal / fully opaque (backward-compatible).
- **Undo**: `undo_manager.gd` snapshots both. In-place `_restore()` calls `applyBlendMode()` after
  `setWiggle()`; the load and `_restore_full()` paths set the fields before `add_child`, so `_ready()`
  → `applyBlendMode()` applies them.

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

`_apply_wiggle_to_children()` places each directly-linked child (`getAllLinkedSprites()`) at `appendage.sample_local(t)`, where `t` is the child's rest distance along the appendage; rotation follows the local chain tangent. The hidden sprite is held at identity so its local space matches the appendage's. Deeper descendants follow for free via the scene tree.

> Updated: 2026-06-10 — **Linked children are now reparented so they stay visible, and they always ride the bend** (the per-layer *Linked layers follow* toggle was removed; `wiggleChildrenFollow` persists but is unused). Linked children are parented under the layer's `Sprite2D`, which wiggle hides (`sprite.visible = false`) — so the whole subtree vanished. `_attach_wiggle_children()` (called each frame from `_update_wiggle`) reparents direct linked children off the Sprite2D onto **`DragOrigin`** (visible, and where the mesh lives), capturing each child's authored rest offset first; `_release_wiggle_children()` (now called from `_set_wiggle_active(false)`) reparents them back under the Sprite2D and restores that rest exactly (no drift). **Caveat:** a child that was clip-masked by this layer (`setClip` → `sprite.clip_children`) loses the mask while the parent wiggles (clipping to a deforming mesh isn't supported) and re-clips once wiggle turns off.

### Parameters (`spriteObject.gd`)

User-facing units (degrees / friendly ranges), mapped to the chain in `_wiggle_params()`: `wiggleEnabled`, `wigglePath` (traced rest centerline, texture-px) + `wigglePathWidths` (per-point half-widths, the mesh band — auto-fit to the art's silhouette via `_fit_widths_to_content()`, which samples the rendered rest path and pools a conservative width envelope back to the control points) + `wiggleThickness` (UI label **coverage** — uniform multiplier over the band; 1.0 = silhouette fit, <1 trims, >1 pads; no distortion since the mesh maps art directly), `wiggleSegments` (UI label "Bones" — chain joints resampled from the path), `wiggleStiffness` (spring constant — also scales the rotation-speed cap + tip softening, so it doubles as the "snappy vs smooth propagation" knob), `wiggleDamping`, `wiggleBendFocus` (→ comeback_speed / "springiness"), `wiggleShapeReturn` (→ rest_return / "shape return" — an over-damped pull back to the rest shape, distinct from the spring: holds/returns the original shape without overshoot; 0 = free/floppy, 1 = rigidly holds rest), `wiggleWeight` (gravity droop), `wiggleMaxBend` (max angle/joint), `wiggleWagEnabled` / `wiggleWagAmount` (base-sway amplitude) / `wiggleWagSpeed` (auto-wag), `wiggleReactivity` (→ root-follow smoothness; higher = laggier whip), `wiggleChildrenFollow`. `segment_length` is derived from the path length; `subdivision` is fixed at 4. The **Ribbon** group in the Physics tab holds Edit-path / Auto-fit / coverage. **Auto-fit** (`_auto_fit_wiggle_path`) traces the artwork's **centerline (medial spine)** — `_trace_centerline()`: PCA for the main axis, start from an interior spine point, walk both ways re-centering on each perpendicular cross-section (so it follows curves), Douglas-Peucker to control points — then sizes the band to the silhouette; it adds as many points as the curve needs (a straight tail → 2-3, a curved one → ~8-12). Falls back to a straight principal-axis path if the content can't be traced. `_extend_ends()` then pushes each endpoint outward along its tangent by the opaque overhang there (`_content_reach`), so the band's flat end-cap reaches past a **pointed/rounded tip** instead of clipping it (a flat attachment with no overhang is left in place, so the wiggle root isn't shoved off the layer). `_orient_path_to_origin()` then flips the path so its **root** (index 0 = the wiggle pivot) is the endpoint nearest the **layer origin** (`size/2 − offset` in texture-px) — the trace's end order is otherwise arbitrary (PCA-axis sign), which can root a tail/ear at its tip; placing the origin near the base now picks the start. Normal point/width edits preserve the current `wigglePathWidths`; auto-width recalculation only runs from the explicit **Auto-fit to content** action or initial pathless setup. The amber width grips remain for manual per-point override / excluding part of a layer.

> Updated: 2026-06-01 — **Trace + width-fit hardening (both verified offscreen on a curved tapering tail).** (1) `_spine_walk` now terminates at tips: a normal step advances ~`trace_step`, so if re-centering snaps the point **> `trace_step * 3`** across a gap it means the walk stepped off a tip and `_spine_center` (which searches the whole image perpendicular) grabbed distant content — i.e. a **U-turn that re-traces the whole shape back to the other tip**. We break instead of following the jump. Before this, an arc traced ≈2× its length (out to one tip, U-turn, back to the other), and `smooth_path` of that doubled polyline looped — the band ballooned/looped at the base. (2) `_fit_widths_to_content` now measures coverage **perpendicular to the smoothed band centerline** (`smooth_path(wigglePath,10)`, nearest-point normal) rather than the raw control polyline, and marches with `_content_reach(..., threshold = 0.1)` (was 0.25) so the probe direction matches the band's real normal and reaches the anti-aliased silhouette edge, then grows the half-width `(ext + 2px) * 1.1` (~10%, 2026-06-01 — the bare fit still read slightly small). Fixes the earlier under-coverage ("too conservative"). `_content_reach` gained a `threshold` param (default 0.25 keeps the trace's centering behaviour).
>
> Updated: 2026-06-02 — **Coverage envelope fit.** `_fit_widths_to_content()` now measures silhouette reach at every sample of the same resampled/smoothed rest path the mesh renders (`_wiggle_mesh_rest_path()`), then pools each sample's required width back to the neighbouring control widths. This makes auto-fit conservative across curved segments and between sparse handles, avoiding the old case where a bulge between two control points clipped unless the user globally over-inflated **coverage**. The editor preview also no longer applies `wiggleThickness` twice, so the pink band matches the actual mesh coverage.
>
> Updated: 2026-06-02 — **Auto-fit-only width recalculation.** Moving/inserting/removing centerline points and dragging amber width grips now preserve the existing per-point widths. `_exit_path_edit()` no longer calls `_fit_widths_to_content()`; auto-width recalculation only happens from the explicit **Auto-fit to content** action (plus first-time pathless setup), so other handles do not jump while editing.

### Save/Load/Undo

All `wiggle*` fields persist alongside the eye-tracking fields (same sites in `main.gd` save dict + load, and `undo_manager.gd` snapshot / `_restore` / `_add_sprite_from_data`). `wigglePath` / `wigglePathWidths` are Packed arrays, serialized with `var_to_str` / `str_to_var` for the JSON save (raw `.duplicate()` in the in-memory undo snapshots); `wiggleThickness` is a scalar. All loaded behind `has()` guards, so old saves load with defaults (and `_auto_fit_wiggle_path()` gives any path-less wiggle layer a usable path on first activation). `_restore()` calls `setWiggle()` to rebuild/clear the ribbon for the restored state.

## Animation (clips)

> Updated: 2026-06-10 — Per-layer keyframe/transform animations. A layer holds a list of **animation clips** (`spriteObject.animClips`, an Array of Dictionaries) evaluated each frame by `effects/animation/layer_animator.gd` (`LayerAnimator`, RefCounted). Two **shapes** — `twitch` (one-shot half-sine ease out-and-back) and `oscillate` (continuous sine) — on two **channels** — `rotation` (degrees) and `translation` (pixels). Four **triggers**: `always` (idle; oscillate runs continuously, twitch loops), `random` (blink-style per-frame probability `randi() % chance`), `key` (a bound key via `BackgroundInputCapture`), `manual` (the Test button). Designed extensible: new shapes/channels/triggers are added in one place each.

### Composition — where it applies
`LayerAnimator.evaluate(clips, tick, delta)` sums every clip into `rot` (radians) + `trans` (px), read each frame in `spriteObject._process` as `_animRot` / `_animTrans`. **Rotation rides `dragOrigin.rotation`** — the outermost transform on the layer — so it rotates the visible `Sprite2D` AND (for wiggle layers, where the Sprite2D is hidden) the deformable mesh + chain anchor, driving the verlet chain into secondary motion (a twitch whips a wiggly ear). It composes *outside* `sprite.rotation = _micRot + _eyeTrackRotation` (mic sway + eye-track stay inner). **Translation feeds `wob.position`** in `wobble()` (the base, before the eye-track offset is added) — exactly where the legacy wobble wrote. Suppressed while tracing a wiggle path (`_wigglePathEditor != null`).

### Legacy wobble migration
The old free-running wobble (`xFrq/xAmp/yFrq/yAmp`, a free sine on `wob.position`) is subsumed: it maps 1:1 to an `always`/`oscillate`/`translation` clip carrying `ampX/freqX/ampY/freqY` (identical `sin(tick*freq)*amp` math, so migrated avatars look pixel-identical). On load, when a save has **no `animClips` key**, `spriteObject.migrateLegacyWobble()` folds nonzero wobble into such a clip; the legacy fields are left intact (older app builds still read them) and `wobble()` no longer reads them. New saves carry `animClips` and skip migration. **Only the wobble migrated** — the bounce-reactive rotation (`rdragStr` / `rLimitMin/Max`), squash (`stretchAmount`), and drag-lag (`dragSpeed`) remain physics (now under the left sidebar's **Reactive** tab), NOT animations.

### UI — left sidebar tabs
`sprite_viewer.gd` gained a `SidebarTabBar` (reused from the right sidebar) below the sprite-sheet section: **Animation** and **Reactive**. Preview / Position / Normal-map / sprite-sheet frames+speed stay always-visible above the tabs. **Animation** content is built by `ui_scenes/spriteEditMenu/animation_clip_panel.gd` (`AnimationClipPanel`, RefCounted): a clip **list** with **+ New** / **Remove**, and an **inspector** for the selected clip (name, channel, shape, motion params, trigger → chance slider *or* Bind-key button, **▶ Test**). It rebuilds on a structural signature change (sprite / clip count / selection / channel / shape / trigger) and otherwise only refreshes live values (so undo of a slider edit shows without rebuilding mid-drag). **Reactive** holds drag / rotational-drag + limits / squash. `_layout_panel()` lays out the header sections, the tab strip, then the active tab's sections (re-run on tab switch, freeing prior dividers first); the active tab persists in `Saving.settings["leftSidebarTab"]`.

### Triggers (keys) & persistence
Key binding mirrors the costume-hotkey flow: the inspector's Bind button sets `Global.awaitingAnimKeyBind` + `Global.animKeyBindClip` (a reference to the live clip dict); `main.gd`'s `_on_background_input_capture_bg_key_pressed` writes the next captured key into it. At runtime that same handler scans the `"saved"` group and calls `spriteObject.triggerAnimationKey(key)` (guarded by `Global._is_any_field_focused()` and the costume-bind state, so it doesn't fire while typing or binding). `animClips` persists as **one field** via `var_to_str` / `str_to_var` across all sites — `main.gd` save / load / duplicate and `undo_manager.gd` snapshot / `_restore` / `_add_sprite_from_data` — deep-copied (`.duplicate(true)`) in dup + undo so snapshots don't alias the live array.

### Curves & preview graph
> Updated: 2026-06-10 — A twitch clip carries a **`curve`** field selecting its easing envelope from `LayerAnimator.envelope(curve, ph)` (a `static func`, the single source of truth): `smooth` (half-sine), `ease` (rounded plateau), `snap` (fast attack/slow release), `spring` (overshoot + damped bounce through rest), `pulse` (linear triangle). The runtime (`_eval_twitch`) and the inspector preview both call it, so the preview is exact. Append-only (add a `match` case + a `_CURVES`/`_CURVE_LABELS` entry). The animator tracks live per-clip state in `_rt[i]` (`active` + normalized `ph`) for **both** shapes (twitch: progress 0→1; oscillate: phase within one period) and exposes it via `LayerAnimator.sample(i)` → `spriteObject.getAnimSample(i)`. The inspector adds a **Curve** dropdown (twitch only) and an `AnimationCurveGraph` (`ui_scenes/spriteEditMenu/animation_curve_graph.gd`, `Control` + `_draw`): it plots the curve (value vs normalized time) and a **dot that rides it** whenever the clip plays — Test or organic trigger — by polling `getAnimSample` each frame (only while `is_visible_in_tree()`, so the hidden Reactive tab costs nothing). `curve` rides in `animClips` (no new persistence sites) and is part of the inspector's structural signature so changing it rebuilds the preview.
