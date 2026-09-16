# PNGTuberPlus Architecture Guide

> Last updated: 2026-08-06 — Phase 8 release and maintenance contracts

## Overview

PNGTuberPlus is a Godot 4.6 desktop application for creating and performing with PNGTuber avatars. The supported and CI-pinned patch release is Godot 4.6.3. Users import sprite images (PNG, APNG, PSD), arrange them into a layered rig, and the app responds to microphone input with bounce, wobble, blink, and eye-tracking animations.

> Updated: 2026-08-06 — Godot 4.6 is the single engine baseline. `scripts/run_tests.sh` imports the project and runs the headless GDScript suite; `scripts/run_performance.sh` records repeatable CPU microbenchmarks under `.artifacts/`. CI runs the tests on macOS, Windows, and Linux using the official Godot 4.6.3 binaries. Native code must use the repository's pinned Godot 4.6 `godot-cpp` submodule revision. The duplicate top-level `godot-ndi/` package was removed; `addons/godot-ndi/` is the sole NDI integration. The obsolete bundled Git editor extension was also removed; source-control operations use the installed Git tooling and no longer add a native library to application/editor startup.

> Updated: 2026-08-06 — `scripts/run_release_checks.sh` composes unit/source
> contracts, performance budgets, and a standalone production resource-pack
> launch. Export presets select `main.tscn` and explicitly include indirect
> script/scene resources, keeping developer saves and imported artwork out of
> release packs. CI runs the export/launch smoke on all three desktop hosts.

> Updated: 2026-08-17 — Export `include_filter` covers whole source directories
> (`autoload/*`, `main_scenes/*`, `ui_scenes/*`, `effects/*`, `ndi/*`,
> `shader/*`, `icons/*`, `font/*`, the Stream Deck addon) plus the three
> `*.gdextension` manifests, with `exclude_filter="ui_scenes/light/*"` for the
> dormant light work. Per-file patterns had silently dropped whatever a release
> added later: v1.7.0a exports were missing `main_scenes/menu_actions.gd`, the
> new `ui_scenes/settings/` assets, and — because a `.gdextension` manifest is
> only exported when the filter names it — every native library (NDI, PSD,
> background input). Godot copies a manifest's platform libraries beside the
> binary only when the manifest itself is packed, so those patterns are the
> switch that ships native features. `run_export_smoke.sh` now mirrors the
> native libraries into the smoke directory before launching the pack; without
> them the macOS loader aborts on the missing dylib.
>
> The filter must also name `default_bus_layout.tres`: project settings
> reference it by UID and no export filter follows that, so the first v1.7.0a
> build booted with a Master bus alone. `MicrophoneMonitor` sets
> `player.bus = &"MIC"`, which then falls through to Master and plays the
> microphone out of the speakers, and `get_bus_index(&"MIC")` returns -1, so
> `_refresh_spectrum()` finds no analyzer and the level meters read zero. Any
> resource reached only through project settings needs the same treatment.

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
│   │   ├── avatar_controller.gd   Avatar assembly, edits, costumes, save data
│   │   ├── capture_controller.gd  Screenshot, recording, FFmpeg ownership
│   │   ├── import_controller.gd   PSD/APNG/PNG workers and import dialogs
│   │   ├── import_matcher.gd      Pure replacement name matching
│   │   ├── save_controller.gd     Save dialogs, workers, session recovery
│   │   └── viewport_controller.gd Window, pan, zoom, edit/view layout
│   ├── EditControls.gd            Top menu bar (edit mode)
│   ├── ControlPanel.gd            Right-side streaming panel (view mode)
│   ├── Tutorial.gd                First-run tutorial overlay
│   └── originLineDrawing.gd       Origin crosshair lines
│
├── ui_scenes/
│   ├── common/
│   │   ├── menu_bar.gd           Shared edit/player menu bar and meters
│   │   ├── form_ui.gd            Constructed settings-form primitives
│   │   ├── modal_dialog.gd        Shared modal layout and input guard
│   │   ├── tab_bar.gd             Shared sidebar/settings tabs
│   │   └── sidebar_ui.gd          Shared styles, bounds, and chrome hit tests
│   ├── mouse/
│   │   └── mouse_cursor.gd       Click detection & tooltip in edit mode
│   ├── selectedSprite/
│   │   ├── spriteObject.gd       Scene-facing layer lifecycle facade
│   │   ├── sprite_collision_builder.gd Alpha/fallback hitbox construction
│   │   ├── sprite_collision_runtime.gd Shape lifecycle and active-state coordination
│   │   ├── sprite_hierarchy.gd   Pure child/descendant lookup policy
│   │   ├── sprite_rest_pose.gd   Authored rest pose for the edit-mode motion pause (2026-09-16)
│   │   ├── sprite_visibility_policy.gd Pure talk/blink/costume visibility
│   │   └── sprite_visual_runtime.gd Texture, normal, blend, and depth synchronization
│   ├── spriteEditMenu/
│   │   ├── sprite_viewer.gd      Left sidebar scene facade/layout (265px)
│   │   ├── selection_presenter.gd Selected-layer preview and field synchronization
│   │   ├── normal_map_panel.gd   Normal-map import/clear component
│   │   ├── rotation_preview_renderer.gd Rotation-circle texture construction
│   │   └── chain.gd              Visual line during reparenting
│   ├── spriteList/
│   │   ├── viewer.gd             Right sidebar scene facade/layout (310px, resizable)
│   │   ├── layer_tree_controller.gd Layer rows, hierarchy, filtering, and scroll
│   │   ├── eye_tracking_panel.gd Tracking controls and target presentation
│   │   ├── layer_details_panel.gd Details controls and NDI reference policy
│   │   ├── physics_tab.gd        Physics tab — wiggle controls
│   │   └── sprite_list_object.gd Individual list item with thumbnail
│   ├── psdImport/
│   │   ├── legacy_replace_prompt.gd Legacy full-canvas compatibility prompts
│   │   ├── psd_import_dialog.gd     PSD layer selection dialog (import flow)
│   │   └── replace_review_dialog.gd Unified replace review dialog (PSD/folder/PNG)
│   ├── settings/
│   │   ├── settings_menu.gd      Constructed settings scene facade
│   │   └── *_settings_tab.gd     Audio/display/motion/hotkey/output components
│   ├── zIndex/
│   │   └── z_index_editor.gd     On-canvas z-index entry overlay
│   ├── pushUpdates/
│   │   └── push_updates.gd       On-screen notification system
│
├── autoload/                      Global singletons (autoloaded)
│   ├── global.gd                  Central state: mic, selection, input, modes
│   ├── saving.gd                  JSON persistence, settings, save/load
│   ├── undo_manager.gd            Transactional undo/redo (50-state history)
│   ├── domain/sprite_state.gd     Canonical sprite property compatibility map
│   ├── domain/sprite_registry.gd  Canonical live layer enumeration/ID index
│   ├── domain/selection_state.gd  Selected layer and click-cycle state
│   ├── domain/mutation_commands.gd Canonical undoable mutation commands
│   ├── domain/legacy_canvas_compat.gd Full-canvas rig detection and replace placement
│   ├── input/input_commands.gd    Pure key/device command decoding
│   ├── import/import_limits.gd    Shared binary import resource budgets
│   ├── psd_parser.gd              PSD file parser (background thread)
│   ├── apng_parser.gd             Bounded APNG parser and compositor
│   └── defaultAvatarData.gd       Built-in default avatar data
│
├── shader/
│   └── wobble.gdshader            Wave oscillation effect
│
├── effects/
│   ├── animation/layer_animator.gd Per-layer transform animation evaluator
│   └── wiggle/                    Wiggly-appendage physics (per-layer)
│       ├── wiggle_appendage.gd    Deformable textured mesh (Polygon2D) + verlet/angular-spring chain
│       ├── wiggle_geometry.gd     Pure path tracing, coverage, projection
│       ├── wiggle_path_editor.gd  On-canvas ribbon-path tracer (Global.wigglePathMode)
│       └── wiggle_runtime.gd      Live mesh, editor, and child-follow ownership
│
├── ndi/                           NDI video output system
│   ├── ndi_output_manager.gd      SubViewport + Camera + NDIOutput orchestrator
│   ├── ndi_output_geometry.gd     Pure crop/output sizing calculation
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
│   ├── dependencies.md            Native/runtime provenance and upgrade policy
│   ├── quality_baseline.md        Toolchain, tests, performance, dependency risks
│   ├── refactor_plan.md           Phased execution and acceptance gates
│   └── save_format.md             Versioned avatar/settings compatibility contract
├── tests/
│   ├── integration/               Isolated production-scene behavioral runner
│   ├── performance/               Pure, avatar-load, and lifecycle benchmarks
│   ├── native/                    Native extension lifecycle smokes
│   └── unit/                      Headless unit and source-contract suites
├── scripts/                       Local quality-gate entry points
├── CONTRIBUTING.md                Setup, acceptance gates, and change contracts
└── project.godot                  Godot project configuration
```

> Updated: 2026-08-17 — The directory map reflects the constructed menu and
> settings rebuild and the production-scene integration/performance harness.

> Updated: 2026-08-17 — The main-scene controller map includes the completed
> avatar and import boundaries from Phase 11.

---

## Autoload Singletons

Registered in `project.godot` under `[autoload]`:

| Singleton          | File                           | Purpose                                              |
|--------------------|--------------------------------|------------------------------------------------------|
| `DefaultAvatarData`| `autoload/defaultAvatarData.gd`| Built-in default avatar data                         |
| `Saving`           | `autoload/saving.gd`          | Avatar persistence (JSON + base64 images), settings  |
| `Global`           | `autoload/global.gd`          | Central state manager, mic input, selection, input routing |
| `UndoManager`      | `autoload/undo_manager.gd`    | Snapshot-based undo/redo with image caching           |

Additional parsers (not autoloaded, instantiated on demand):
- `PSDParser` (`autoload/psd_parser.gd`) — threaded PSD file parsing
- `APNGParser` (`autoload/apng_parser.gd`) — APNG detection and sprite sheet assembly

> Updated: 2026-08-06 — `Global` remains the compatibility-facing application
> state autoload, but runtime ownership is delegated under `autoload/runtime/`.
> `MicrophoneMonitor` owns exactly one tracked capture player, resolves the MIC
> spectrum analyzer by bus/type instead of numeric indexes, applies the level
> envelope and speaking transitions, validates device selection, and owns a
> generation-guarded delayed restart. It never frees unrelated autoload
> children and shuts down explicitly. Player shutdown clears the native stream
> before deletion; standalone release smoke sessions do not open the host
> capture device. `BlinkScheduler` owns deterministic blink timing and
> random-roll evaluation. `Global` mirrors their established public
> fields/signals so existing sprite/UI polling remains compatible. Toasts flow
> through `Global.notification_requested` rather than a retained UI-node
> pointer. `main.gd` attaches/detaches itself explicitly so scene-bound Global
> references and interaction modes are cleared during shutdown or scene swaps.
> Pure transition tests live in `tests/unit/test_runtime_services.gd`.

> Updated: 2026-08-17 — `Global` owns a `SpriteRegistry` populated by each
> sprite's ready/exit lifecycle. It is now the canonical enumeration and lookup
> boundary for production code; the `"saved"` group remains on sprite roots for
> scene/debugging compatibility. The registry prunes invalid objects,
> atomically handles reused IDs, and rebuilds the set of eye-target IDs at most
> once per process frame. `SelectionState` separately owns the held layer and
> repeated-hit cycling. Feature scripts read the compatible
> `Global.heldSprite` property but mutate it only through
> `select_sprite()`/`clear_selection()`, and selected nodes are invalidated when
> they leave the registry. `Global.main`, `spriteEdit`, `spriteList`, `mouse`,
> and `chain` remain the canonical shared node references, now registered and
> cleared through paired attach/detach methods. Notifications use
> `notify_user()` and the existing lifecycle-safe signal; text-focus, Z-index
> capture, reparent, wiggle-path, eye-target, and key-capture state expose
> purpose-named methods rather than private-field calls. Boundary contracts live
> in `tests/unit/test_application_boundaries.gd`.

---

## Main Scene Hierarchy

Entry point: `main_scenes/main.tscn` controlled by `main_scenes/main.gd`

Key child nodes:
- `OriginMotion/Origin` — root container for all sprites; bounces vertically on speech
- `Camera2D` — main viewport camera (zoom 10%-400%, middle-mouse pan)
- `EditControls` — top menu bar in edit mode
- `ControlPanel` — viewer mode's top menu bar, plus its popups and zoom readout
- `SpriteViewer` — left sidebar sprite editor (child of EditControls)
- `SpriteList` — right sidebar layer tree
- `Lines` — origin crosshair drawing
- `PushUpdates` — floating notification system
- Various file dialog nodes

> Updated: 2026-08-06 — `main.gd` is the compatibility-facing scene
> coordinator and delegates independent lifecycles under
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

> Updated: 2026-08-17 — `main.gd` is now a 597-line lifecycle and scene-signal
> facade. `AvatarController` owns transactional avatar assembly, validation,
> hierarchy reconstruction, save-data construction, edit commands, costume
> application, and its decode-worker shutdown. `ImportController` owns the
> PSD/APNG/PNG pipelines, bounded preparation workers, native file dialogs,
> replacement review, and import cancellation/shutdown. `ImportMatcher` is the
> pure, deterministic duplicate-name matching policy shared by replacement
> flows. All receive their scene and autoload dependencies in `setup()` and
> existing signal method names remain thin `main.gd` facades. A duplicated
> sprite must set `_skip_ready_reparent` before `add_child()`: `_ready()` runs
> synchronously on insertion, so setting the guard afterward leaks the deferred
> reparent timer and can move the clone unexpectedly. Production-scene tests
> exercise load/save, duplicate, replacement, costume, hierarchy, and shutdown
> through the real controller graph.

> Updated: 2026-08-18 — **Legacy full-canvas replace compatibility.** Rigs built
> before PSD import existed carry one full-canvas PNG per layer: the artwork sits
> inside its own transparent padding, so layers line up by construction. PSD
> layers are cropped to their own bounds, so replacing a legacy layer with one
> drops the padding that was carrying its placement. `ImportController` now runs
> `LegacyCanvasCompat.evaluate()` on the live rig before the review dialog opens.
> Uniform still-layer sizing plus at least one filesystem-backed layer path
> identifies the legacy shape; a PSD authored at other dimensions is refused
> outright through `legacy_replace_prompt.gd`, since cropped layers cannot be
> re-aligned to a canvas of a different size. Otherwise the user chooses
> compatibility placement, a plain replace, or cancel, and the answer rides to
> `AvatarController.apply_replacement()` as `legacy_canvas`.
>
> The placement is arithmetic, not re-padding: padding every layer back out costs
> a full-canvas texture and alpha scan per layer and leaves the rig permanently in
> the legacy shape. The layer's Sprite2D is centred, so its artwork centre sits at
> local `offset` and the node origin (the rotation/drag pivot) lands at texture
> pixel `size/2 - offset`. Holding `position` still and re-deriving
> `offset = offset + (layer centre - canvas centre)` keeps that pivot on the canvas
> coordinate it already occupied. Compensating with `position` instead would drag
> the pivot onto a different part of the artwork and carry every linked child
> layer with it. The correction is applied per layer (`is_legacy_layer`), so a rig
> that mixes legacy layers with later cropped ones corrects only the former, and
> it degenerates to a no-op when the replacement spans the whole canvas.
> `replaceSpriteFromData()` takes the shift as an optional third argument and also
> moves the wiggle rest path, which is stored in texture pixels
> (`WiggleRuntime.remap_path`). `ImportMatcher.items_from_psd()` now drops `_NRML`
> layers, which previously entered a replace as ordinary visible artwork;
> `psd_import_dialog` asks `ImportMatcher.is_normal_layer()` for the same rule.
> Normal maps are still cleared on a size change, so a legacy replace drops them.
> Placement math and detection are covered in `tests/unit/test_pure_behavior.gd`;
> the production runner verifies a marker pixel lands on the same screen position
> across a cropped replacement.

> Updated: 2026-08-06 — Global background capture is a dynamically instantiated
> optional boundary. `main.gd` checks for `BackgroundInputCapture` through
> `ClassDB`, connects its two signals when available, and otherwise keeps
> foreground input working with one warning. `main.tscn` no longer requires the
> native custom class merely to instantiate the application.

---

## Edit Mode UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Switch to Player     Import | Duplicate | Replace | Save | …  │  ← EditControls menu bar (28px)
├──────────────┬──────────────────────────┬───────────────────┤
│              │                          │  [speak][blink]   │
│  Sprite      │                          │  [link][unlink]   │
│  Viewer      │      Canvas              │  [trash]          │
│  (left       │      (sprites rendered   │───────────────────│
│  sidebar,    │       here, click to     │  Layer list       │
│  265px)      │       select)            │  (scrollable)     │
│              │                          │───────────────────│
│  - 2D preview│                          │  Costume buttons  │
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

> Updated: 2026-08-17 — **Both sidebars are scene facades below 700 lines.**
> The right facade delegates row creation/hierarchy/filtering/scrolling to
> `LayerTreeController`, tracking scope/controls/tooltip/pick-whip behavior to
> `EyeTrackingPanel`, and layer flags to `LayerDetailsPanel`; its established
> `Global.spriteList` methods remain compatibility wrappers. The left facade
> delegates selected-layer preview and field synchronization to
> `SelectionPresenter`, normal-map file actions to `NormalMapPanel`, and
> one-time circle textures to `RotationPreviewRenderer`, alongside the existing
> animation component. `Global.spriteEdit` and its `setImage()`,
> `setLayerButtons()` surface remains stable. The left
> scene no longer instantiates its replaced 3D viewports, old top buttons,
> legacy wobble sliders, costume strip, visibility controls, or eye controls;
> old saves still migrate legacy wobble data in the sprite runtime. Extracted
> components receive their state/services explicitly and never reach into a
> sibling panel's private fields.

---

## Menu Bar (both modes)

> Added: 2026-08-07 — Viewer mode rebuilt as a constructed layout on a shared menu bar.

Both modes draw their top bar from one component, `ui_scenes/common/menu_bar.gd`
(`class_name AppMenuBar extends Control`; the name is prefixed because Godot 4
already ships a native `MenuBar`). Chrome, item styling, resize behaviour and
popup placement live there once, so the two bars cannot drift apart.

**Layout is constructed, not placed.** Three container zones. The side zones ride
a row pinned to both edges; the center zone sits in its own full-width
`CenterContainer`, so it centres on the **window**:

```
┌──────────────────────────────────────────────────────────────┐
│ left zone                center zone               right zone│  28px
└──────────────────────────────────────────────────────────────┘
   pinned left        centred on the bar            pinned right
```

> Updated: 2026-08-07 — The center zone used to sit between the two side zones,
> balanced by expanding spacers. That reads as centred only while the two sides
> happen to be the same width: once the viewer bar's right zone grew to hold the
> meters and Settings, it silently dragged the centre strip left. The center zone
> now has its own container spanning the bar, and is centred to within a pixel
> regardless of what the sides hold.

Edit mode keeps its editing actions in the center and puts the mode switch in the
left zone; the viewer bar uses all three.

- **Edit bar** (`main_scenes/EditControls.gd`): `Switch to Player` left; `Import Duplicate Replace | Save Load | Clear Reset` center; `Pause Motion` right. The file now only declares items; it owns no styling.
- **Viewer bar** (`main_scenes/ControlPanel.gd`): `Switch to Editor` left; `Save Load | Clear Reset` center; the `Duration` and `Level` mic meters then a gear icon for Settings, right.

> Added: 2026-09-16 — **Motion pause** (edit bar, right zone). A toggle button
> that holds the whole avatar at its authored rest pose so a rig can be edited
> against what it actually looks like at rest. It sets `Global.motionPaused`; every
> consumer reads `Global.motion_paused()`, which also requires `main.editMode`, so
> swapping to player mode resumes motion without clearing the toggle. The flag is
> runtime-only: never saved, never in undo, and cleared by `Global.detach_main`.
> Two consumers. `main.gd` `_process` folds it into the existing NDI crop freeze
> branch, pinning `OriginMotion.position.y`, `yVel` and `bounceChange` at rest.
> `spriteObject._process` takes an early branch that calls
> `SpriteRestPose.apply(self)` (`ui_scenes/selectedSprite/sprite_rest_pose.gd`)
> instead of advancing anything: the animator is reset and `_animRot`/`_animTrans`,
> eye-track offset/rotation and `_micRot` are zeroed, `wob` returns to origin, the
> dragger and `DragOrigin` snap onto it, sprite rotation/scale reset, frame
> animation returns to frame 0, and `_wiggleRuntime.rest()` snaps the chain onto
> its rest path and re-places linked children on it (which by construction lands
> each child exactly where it was authored). `tick` does not advance, so frame
> animation and the wiggle auto-wag are frozen too. The rest pose is re-applied
> every frame rather than once on entry, so a layer moved or re-rigged while
> paused still shows its true rest position. The rest pass arms `_force_drag_snap`
> so unpausing does not read the pause as one huge frame of movement and feed it
> into rotational drag and stretch. The selection chrome moved out of `_process`
> into `_update_selection_gizmos()` so both the live and paused paths draw it.

> Updated: 2026-08-17 — The two mic controls are **threshold markers, not
> knobs**. Each is a meter with a slider riding on it, both on the same scale
> (`SettingsSchema.MIC_LEVEL_RANGE` 0.2, `MIC_DURATION_RANGE` 1.0), and the limit
> handed to `MicrophoneMonitor` IS the thumb position: a trigger holds while the
> bar behind the thumb has reached it. `Level` compares the live signal, so the
> avatar speaks once the bar arrives at the thumb; `Duration` compares the decay
> that follows a trigger, so a thumb further left holds the mouth open longer.
> Two things this depends on. The meter spans exactly the grabber's travel
> (`METER_EDGE`), because with `center_grabber` the grabber's centre crosses the
> slider's whole rect, so a full-width meter drifted up to 7 px from the thumb;
> alignment was measured in rendered pixels, not by eye. And settings schema 2
> mirrors the stored `volume` / `sense` once, since schema 1 stored
> `range - thumb` (the slider read as a sensitivity knob). Defaults moved to the
> mirrored values, so upgrades keep the thresholds they had.

> Updated: 2026-08-07 — The viewer bar gained the avatar file actions. Both bars
> now take `Save Load | Clear Reset` from `MenuActions.add_avatar_file_actions`
> (`main_scenes/menu_actions.gd`), declared once so the two modes cannot drift in
> wording, order, grouping or wiring. On the viewer bar the group comes last in
> the left zone, which keeps the destructive pair furthest from the frequently
> pressed mode switch and puts it in the same relative position as in edit mode.

> Updated: 2026-08-07 — The mode toggle is labelled `Switch to Editor` /
> `Switch to Player`, is toned like any other item, and leads the left zone on
> both bars, so it sits in the same place whichever mode you are in. Moving it
> out of the edit bar's center strip shifts that strip slightly right of the
> viewport centre, because the center zone is centred between the left and right
> zones rather than against the window.

> Updated: 2026-08-07 — Viewer bar rearranged: mode switch far left, the shared
> file actions in the center, and `Duration  Level  Settings` filling the right
> zone so Settings closes the bar opposite the mode switch. The green NDI
> telltale is gone; NDI state is reported in the settings panel's NDI section. The `Mic`
> button is built but hidden pending its move into the settings panel; its device
> popup and right-click mute stay wired so that becomes a relocation rather than
> a rewrite. With the file actions now in the center, the crowding rule can no
> longer assume the center is expendable: `set_collapsible(node)` nominates the
> item that yields, and the viewer bar nominates its mic-meter group.

**Item factories** are the only supported way to put something on a bar:
`add_button`, `add_icon_button`, `add_separator`, `add_label`, `add_group`,
`add_level_meter`.
`set_button_tone` / `set_button_enabled` restyle in place.

**Sizing gotcha.** A `Control` parented to a `Node2D` inherits a zero-sized
anchorable rect, so anchors collapse it to its minimum width. The bar therefore
sets its own `size` from the viewport in `_fit_to_viewport()` (reconnected to
`Window.size_changed`) and positions itself directly. Its children anchor
normally, because their parent is a `Control`.

**Crowding.** Nothing warns when the centred strip runs into a side zone; they
simply draw over each other. `set_collapsible(node)`
nominates the one item that yields, and `_apply_crowding()` hides it when
`zones_fit()` says the zones cannot clear each other, restoring it as soon as
they can. Because the strip is centred on the bar, the binding constraint is the
**wider** side zone, not the sum: two layouts with identical total content can
differ, one fitting when balanced and the other colliding when lopsided. Which item is expendable is the bar owner's judgement, not the
component's: the viewer bar nominates its mic-meter group so the buttons around
it stay reachable, and a bar that nominates nothing never collapses. The
measurement always counts the collapsible item as if it were showing, so hiding
it cannot change the answer and the state cannot oscillate. It re-runs on window
resize and whenever a zone's minimum size changes.

### Auto-reveal (viewer mode only)

The viewer bar hides off the top edge and slides in while the cursor is near the
top of the window. `configure_auto_reveal(true)` arms it; the edit bar stays
pinned. Tunables are constants at the top of `menu_bar.gd`:

| Constant | Meaning |
|---|---|
| `REVEAL_BAND_RATIO` (0.125) | fraction of window height that summons the bar |
| `HIDE_BAND_RATIO` (0.180) | fraction the cursor must leave to dismiss it |
| `BAND_MIN_PX` / `BAND_MAX_PX` | clamp, so the band works on both a tall desktop window and a small avatar window |
| `SLIDE_SPEED` | reveal/conceal rate |
| `LINGER_SECONDS` (2.0) | how long the bar stays up after the cursor leaves |

The hide band is the larger of the two, so the bar cannot flicker on the
boundary. The slide is a `_reveal` float advanced per frame (not a `Tween`), so
re-entering mid-conceal reverses smoothly. `set_pin(key, bool)` holds the bar
open while a popup is open or a slider is being dragged, when the cursor is
legitimately outside the band. Pure helpers `reveal_band()` and `should_reveal()`
are unit tested in `tests/unit/test_ui_components.gd`.

> Updated: 2026-08-17 — Leaving the band no longer dismisses the bar straight
> away. `_linger` carries the seconds the bar is still owed: `next_linger()`
> recharges it to `LINGER_SECONDS` on **any** frame the bar is wanted and drains
> it otherwise, and `_process` holds the bar while it is above zero. Re-entering
> mid-window therefore restarts the count from full rather than resuming it, and
> because a pin counts as "wanted", closing a popup leaves the same reprieve.
> `snap_hidden()` clears it, so returning focus to the window cannot pop a
> deliberately concealed bar back open. Tested through the real `_process`,
> stepped by hand: outside a tree `_wants_reveal()` is false and pins
> short-circuit ahead of it, so a pin stands in for the cursor with no window and
> no mouse involved.

`revealed_height()` feeds canvas hit-testing, so a concealed bar never steals
clicks from the avatar (see Click-to-Select → Panel click-through guard).

### Popups

`anchor_popup(item, popup, size)` hangs a bar-owned popup from the item that
opens it, clamped to the viewport. The settings menu and mic device list are
still their original scenes; only their placement moved here, so a later popup
redesign has one seam to work against rather than scattered literals.

---

## Settings Panel

> Rewritten: 2026-08-07 — `ui_scenes/settings/settings_menu.gd`.

A fixed-size dropdown (420x380) from the menu bar's Settings button, built
entirely from the shared vocabulary: `AppTabBar` for the strip, `FormUI` for the
labelled rows, `SidebarUI` for the palette. It replaced a hand-placed panel whose
children all carried literal coordinates, whose scene file held a 27 KB node tree
including ten spelled-out hotkey rows, and which grew its own background and
shifted its own position as code-built sections were appended to it.

Five tabs are declared in `_TABS`; each is built and refreshed by its matching
`*_settings_tab.gd` component:

| Tab | Contents |
|---|---|
| Audio | input device list, mute |
| Display | background colour presets and picker, texture filtering, max FPS |
| Motion | bounce force/gravity, bounce on costume change, blink speed/chance |
| Hotkeys | the ten costume bindings |
| Output | NDI (enable / width / mode / manual size / source name), recording (format, fps) |

The tab strip is pinned at the top and the active body scrolls, matching the
right sidebar. `setvalues()` re-reads every control from live state; it runs at
startup and again on each open. To add a setting, add a row to the matching tab
component; to add a category, add a component and tab title. The 123-line
`settings_menu.gd` facade owns only the frame, tab visibility, hover state, and
the public `setvalues()`/`awaitingCostumeInput` compatibility surface.

> Updated: 2026-08-17 — Settings persistence and callbacks now live with their
> owning Audio, Display, Motion, Hotkeys, or Output component. Every component
> receives `Global`/`Saving` explicitly, uses `FormUI` rows and the shared
> slider theme, and is constructed as part of the real production settings
> scene. The hotkey component exposes its capture slot through the facade's
> read-only compatibility property, so `main.gd` does not depend on component
> internals.

**Audio tab.** Microphone selection used to be a separate `MicInputSelect` popup
of `mic_select_button.tscn` rows hanging off its own bar button. That scene, its
script and the bar's `Mic` button are all gone; the Audio tab lists
`AudioServer.get_input_device_list()` directly, marks the active device with an
accent dot, and carries the mute toggle that used to be a right-click on the bar
button.

### Shared UI components

`ui_scenes/common/` is the design system. Nothing in it knows about avatars:

| File | Role |
|---|---|
| `sidebar_ui.gd` | palette, geometry constants, slider theme, chrome hit-testing |
| `form_ui.gd` | labelled control rows: sections, sliders, checks, dropdowns, text fields |
| `tab_bar.gd` (`AppTabBar`) | the tab strip, shared by both sidebars and the settings panel |
| `menu_bar.gd` (`AppMenuBar`) | the top bar for both modes |
| `modal_dialog.gd` (`ModalDialog`) | recovery prompt and every progress dialog |

> Updated: 2026-08-07 — The tab strip moved from
> `ui_scenes/spriteList/sidebar_tab_bar.gd` to `ui_scenes/common/tab_bar.gd` and
> was renamed `SidebarTabBar` to `AppTabBar`, since the settings panel now uses
> it too. It builds its children on demand rather than only in `_ready`, so a
> caller may add tabs before the strip enters the tree.

---

## Modal Dialogs

> Added: 2026-08-07 — one modal component, `ui_scenes/common/modal_dialog.gd`.

Session recovery, save/load progress, PSD/APNG import progress and video
encoding all build from `ModalDialog`. It replaced two near-identical builders
(`main._create_progress_dialog` on the UI layer and `main._create_import_progress_dialog`
in world space) whose children were placed by hand and whose palettes had drifted
apart.

- Constructed: a viewport-covering `Control`, a `MOUSE_FILTER_STOP` scrim, and a `CenterContainer` holding the panel. It stays centred at any window size with no per-frame repositioning; the old builders recentred from `_process` and still froze at the viewport size they were created with.
- The scrim is the modal input guard. World-space dialogs needed a `canvas_input_blocker` Area2D because they had no scrim; `psd_import_dialog` and `replace_review_dialog` still use that mechanism.

> Updated: 2026-08-17 — What actually stops canvas selection during a world-space
> dialog is `main.isFileSystemOpen()`, cached each frame into
> `main.fileSystemOpen` and checked at the top of `Global.select()`. Every such
> dialog has to appear in that function; the single-PNG replace prompt did not,
> so clicking the canvas during it moved the replacement onto another layer.
> Dialogs that act on the held layer (both replace prompts) must return true
> there **without** clearing `heldSprite`, and must capture their target when
> they open rather than read the selection when they are answered. Layer rows are
> Controls and never reach the canvas path, so `sprite_list_object._select()`
> checks the same flag. Note the `canvas_input_blocker` guard inside
> `Global.select()` cannot fire from the mouse path: `mouse_cursor` filters those
> areas out of the array before calling it. The group is still what keeps blocker
> areas from being treated as selectable layers.
- `visibility_layer = 2` keeps dialogs out of NDI output, which the save progress dialog previously did not do.
- Callers compose: `set_title`, `add_message`, `add_progress_bar` / `set_progress`, `add_actions`. `main._create_progress_dialog(text)` is the one-line helper for progress dialogs and attaches to `UILayer` itself.

Controllers under `main_scenes/controllers/` are copied into the isolated test
workspace, which has **no global script class registry**. They must reference
other scripts through `preload` (`ModalDialogUI`, `SidebarUIFactory`), never by
bare `class_name`. A bare name compiles in the editor but fails there, and the
failure silently drops the rest of that suite; `test_main_controllers` now opens
with a compile guard that turns this into a visible failure.

> Updated: 2026-08-17 — `scripts/run_tests.sh` now runs two complementary
> layers. The isolated project keeps pure/unit/source contracts deterministic;
> `tests/integration/avatar_scene_runner.tscn` boots `main.tscn` with the real
> autoload and UI graph and exercises the complete avatar loader. The
> `--avatar-integration-test` argument is handled centrally by
> `Saving.is_isolated_session()`: it uses schema defaults, suppresses settings
> persistence and startup recovery, and prevents microphone/device startup, but
> does not replace the production load, worker, sprite, hierarchy, costume, or
> animation paths. Fixtures cover all ten costumes, effective ancestor
> visibility, unsigned IDs/references, nested hierarchy, legacy idle sway,
> rejected duplicate IDs, and a persisted save/load round trip.

---

## Click-to-Select Architecture

Selection in edit mode flows through these components:

1. **`mouse_cursor.gd`** — listens for left-click via `_unhandled_input`, sets `_click_pending`
2. **`_process()`** in mouse_cursor — when `_click_pending` is true, performs a direct physics space query using `PhysicsDirectSpaceState2D.intersect_point()` at the current mouse position
3. **`Global.select(areas)`** — receives the array of Area2D hits, resolves each through `sprite_from_hit_area()` (the single owner of the required three-level parent walk), and delegates repeated-hit cycling and the held layer to `SelectionState`
4. **UI panels update** — SpriteViewer and SpriteList read `Global.heldSprite` each frame to show/hide controls. When `heldSprite` is null, the SpriteViewer disables all sliders/buttons and dims the panel to 35% opacity; all signal handlers also have null guards as a safety net. (Updated: 2026-02-16)

### Selection lifecycle

> Updated: 2026-08-17 — Call `Global.select_sprite()` and
> `Global.clear_selection()` rather than assigning the held-layer property.
> `unregister_sprite()` automatically clears a selected sprite during its exit
> lifecycle, while avatar load, clear, costume, and undo paths clear selection
> before freeing or replacing scene nodes. `SelectionState.changed` is re-emitted
> as `Global.selection_changed` for consumers that need event-driven behavior;
> the existing UI remains intentionally polling-based.

### Cycling down a stack of overlapping layers

> Added: 2026-09-16 — Clicking a stack selects its topmost layer; clicking again
> steps to the next layer down and wraps at the bottom. Two things had to change
> for that to hold on a live avatar.
>
> **The step is anchored to the held layer, not to a stored index.**
> `SelectionState.choose_from_hits` finds the currently selected layer in the new
> candidate list and takes the one after it, falling back to the top when it is
> not there; `_last_hits`/`_hit_index` are gone and `reset_click_cycle()` is now a
> no-op kept for callers. The old index was keyed on the exact ordered candidate
> array, and the avatar never stops moving (bounce, wobble, animation clips), so
> the same screen point resolves to a different array almost every click: measured
> at a human click rate over a moving rig, the list changed on 10 of 12 clicks, and
> each change reset the index to the top. That is what made cycling look broken,
> and a click landing back on the already-selected top layer look like it had not
> registered at all.
>
> **The point query asks for room for every layer.**
> `PhysicsDirectSpaceState2D.intersect_point` keeps 32 results by default and
> silently drops the rest, in broadphase order. Since each layer's collider became
> its whole image rectangle (see below), a rig of canvas-sized layers puts a
> single click point inside far more colliders than that: on a real 54-layer
> avatar, one point sat inside 55 and the query returned 32 of them. Whole layers
> vanished from the candidate list at random, and the set shifted whenever the
> avatar or the camera moved, which is why selection missed, why cycling skipped
> layers, and why nudging the view could make a layer pickable again. The query
> now passes `Global.sprite_count() + 16`, since each layer contributes one shape.
>
> **The candidate ordering is total and stable over time.**
> `mouse_cursor._sort_top_first` orders by z, then depth-first draw order under
> `OriginMotion/Origin`. Godot's sort is not stable and the physics query returns
> hits in broadphase order, which shifts as the avatar moves, so with only z to
> compare, layers sharing a z came back in a different order from one click to the
> next: six distinct orders over twelve clicks, measured. Draw order is the correct
> tie-break because Godot draws equal `z_index` in tree order, so the layer later
> in the tree is the one actually on top.
>
> The order deliberately does NOT read talk/blink fade, which it used to: layers
> whose talk/blink state is not active right now are dimmed to 20% in edit mode
> rather than hidden, and that bucket flips with the microphone and the blink
> timer several times a second. Measured on a real rig with the mic live and the
> avatar standing still, the top of the candidate list alternated on every click
> and the cycle never came down the stack. Stacking order is what the user is
> pointing at, so it is the only thing the order reads.
>
> `mouse_cursor` also gives the alpha test a 3-screen-pixel tolerance ring
> (`PICK_TOLERANCE_PX`). The exact cursor pixel is tried first and decides the
> answer whenever it hits anything; the ring only rescues a click that would
> otherwise resolve to nothing and therefore clear the selection, which a single
> texel sampled on a moving, soft-edged layer regularly did.
>
> Motion pause (see the menu bar section) also holds talk/blink at rest, so the
> shown/dimmed layers stop swapping while a rig is being edited.
>
> `tests/integration/avatar_scene_runner._test_click_cycling` covers this through
> the real pick path (physics broad phase, alpha test, ordering) with the rig in
> motion and only the cursor position injected.

### Mouse filter configuration

Decorative `ColorRect` background panels must have `mouse_filter = MOUSE_FILTER_IGNORE` so they don't consume clicks before they reach `_unhandled_input`. This applies to:

- `EditControls.gd` — `menu_bar_bg` (full-width top bar)
- `sprite_viewer.gd` — `_bg` (left sidebar background)
- `viewer.gd` — `_bg` (right sidebar background)

Interactive controls (buttons, sliders, scroll containers) keep the default `MOUSE_FILTER_STOP` so they still receive input normally.

### Panel click-through guard

> Updated: 2026-06-12. Never select avatar elements behind a sidebar.

Because the sidebar/menu backgrounds use `MOUSE_FILTER_IGNORE` (above), a canvas click over a panel still reaches `mouse_cursor.gd` and runs the physics pick. `mouse_cursor.gd:_is_over_panel()` is the screen-space guard that rejects those clicks: the pick is applied via `Global.select()` only when `!_is_over_panel()`. Previously the guard also let the click through whenever an opaque sprite sat behind the panel, so clicking blank sidebar space (or the gaps between layer-list rows) could select the element behind it; it now blocks unconditionally while over a panel. Both sidebars are always present in edit mode (the left SpriteViewer dims to 35% but stays visible when nothing is selected; the right SpriteList tracks `editMode`) and selection runs only in edit mode, so the guard does not gate on per-panel visibility. Bounds use each panel's live `panel_width`, so they track sidebar resizing.

> Updated: 2026-08-07 — The shared bounds helper is now `SidebarUIFactory.is_over_app_chrome` (was `is_over_editor_chrome`) and covers both modes. In edit mode it reports the sidebars and the menu bar as before. In viewer mode it reports only the menu bar, and only as far as the bar has slid into view: the caller passes `controlPanel.chrome_height()`, which is `0.0` while concealed, so a hidden bar never steals clicks from the avatar underneath it. `Global.isMouseOverSidebar()` no longer short-circuits on `editMode`.

### Layer context menu (right-click a row)

> Added: 2026-09-16 — Right-clicking a row selects that layer and opens
> `ui_scenes/spriteList/layer_context_menu.gd`: Duplicate, Rename, Delete. The
> menu is built per click and frees itself on close, so it never outlives the row
> it belongs to.
>
> It opens at `root.get_mouse_position()`. Godot embeds subwindows in the main
> viewport by default, and an embedded popup is positioned in VIEWPORT
> coordinates; `root.get_mouse_position()` is the cursor in exactly that space
> (`(screen cursor - window position) / content_scale_factor`, measured). Screen
> pixels from `DisplayServer.mouse_get_position()` are far outside a viewport that
> the 1.5 content scale makes smaller than the window, so the menu was clamped
> into the top-right corner. `Control.get_screen_position()` is wrong for the same
> reason.
>
> **Rename** writes `layerName`, a normal layer field: in `SpriteState`'s
> `SIMPLE_FIELDS`, so it is saved, undone and copied by duplication for free, and
> absent from older saves, where it defaults to empty. `spriteObject.displayName()`
> is the one place that decides what a layer is called: `layerName` when set,
> otherwise the image file's name via `SpriteHierarchy.display_name()` (moved
> there from the row, so the layer and its row read one implementation).
>
> **Delete** asks first, through a `ModalDialogUI` prompt. "Also delete the layers
> under it" is always on the prompt and always starts unchecked, greyed out when
> nothing is linked under the layer, so the choice reads the same way every time.
> The sidebar's trash button opens the same prompt.
>
> `avatar_controller.delete_layer(sprite, include_children)` is the one delete
> path. By default the direct children survive: `unlinkChildren` lifts them to the
> root keeping their world position, and they are then re-attached to the deleted
> layer's own parent, so the rig keeps its shape and only the one layer goes. With
> `include_children` the layer and every descendant are freed.

### The list fits the panel

> Added: 2026-09-16 — Rows take their width from the panel, and indentation is
> the first thing to give. Each row's `custom_minimum_size` is height only; it
> used to carry a fixed 290 px width, which meant the rows, and therefore the
> `ScrollContainer` around them (horizontal scrolling is disabled, so its minimum
> width is its content's), refused to shrink with the sidebar. The whole list then
> hung outside the panel, carrying the show/hide buttons off the right edge:
> measured on a deep rig, 26 px over at a 260 px sidebar and 66 px at 220 px, and
> dragging the sidebar wider was the only way back.
>
> `updateIndent(available_width)` treats depth as a budget: the indent spacer gets
> `indent * INDENT_STEP` px (12, the size other tree panels use: VS Code indents 8,
> Blender and Unity 14 to 16), clamped so the row still fits everything it cannot
> give up (the collapse arrow, the thumbnail, the badges, the show/hide button,
> the separations, and a floor for the name). The name gives way first: it
> ellipsizes as the row narrows, and indentation is only compressed once the name
> is down to the width of `MIN_NAME_SAMPLE` ("Ab…") measured in the row's own font,
> so the floor follows the font size rather than being a magic number. Measured on
> a rig nesting five deep, the indentation now survives intact down to a 220 px
> sidebar and only compresses below that. `layer_tree_controller`
> passes the scroll area's width minus its vertical scrollbar, and `reflow()`
> re-clamps every row when the sidebar is resized. The row's `_draw()` guide lines
> read `indentWidth()` rather than recomputing `indent * step`, so they follow the
> clamped positions.
>
> `viewer._apply_size` leaves `container.custom_minimum_size.x` at 0 and gives the
> column `SIZE_EXPAND_FILL`: the scroll container then sizes it, which keeps it
> clear of the scrollbar, and without the fill flag it would settle at the widest
> row's minimum and leave a dead strip down the right of the panel.
>
> `avatar_scene_runner._test_layer_list_fits_panel` chains fixture layers into a
> deep hierarchy and asserts, at three sidebar widths, that no show/hide button
> crosses the panel's right edge and that every name keeps some room.

### Row indentation

> Added: 2026-09-16 — `_apply_order_and_indentation` sets `row.indent` from the
> depth of the row's ancestor chain, and then calls `row.updateIndent()` on
> **every** row. `updateIndent()` is what actually widens the row's indent spacer,
> and it used to be called only for rows that had children of their own, so a leaf
> layer carried the right `indent` value with a zero-width spacer and rendered
> flush against the left edge: a parent appeared indented past its own children.
> The spacer is the first child of the row's HBox, so one write moves the collapse
> arrow, the thumbnail and the name together (measured on a real rig: 19 px per
> level for all three).

### Deleting a layer from the list

> Added: 2026-09-16 — Layers appearing or disappearing reconcile the existing
> rows (`layer_tree_controller.sync_rows`, via `viewer.syncRows()`) instead of
> calling `update_data()` to rebuild the list. Rows whose layer is gone are
> dropped, rows for new layers are added, and the tree is re-flattened and
> re-indented; `apply_collapse_visibility()` re-shows rows whose collapsed
> ancestor has just gone, and a live filter is re-applied. A rebuild clears every
> row and builds the list again a frame later, which blanks the panel and throws
> away both the scroll position and which groups were collapsed: deleting sent the
> user back to the top of a long list, and undoing a deletion visibly flashed the
> whole panel. Deletion, duplication and undo restores all go through the
> reconciler; `update_data()` stays for avatar loads and costume switches.
>
> The z sort breaks ties on registry order (insertion order, which does not move
> when a layer is removed, nor when a layer is reparented: `register()` keeps an
> already-registered sprite where it is). That order is therefore the list's
> tie-break, so a layer that belongs beside another one asks for it explicitly
> through `Global.place_sprite_after()`. Duplication does, since a duplicate
> carries the source's z and would otherwise appear at the bottom of everything
> sharing it rather than next to the layer it was copied from. Godot's sort is not stable and
> rigs routinely share one z across many layers (20 of 54 on a real avatar), so a
> bare `a.z > b.z` reshuffled those layers on every rebuild: the list came back in
> a different order with a different row at the top.
>
> Covered by `avatar_scene_runner._test_layer_list_deletion`, which flattens every
> layer to one z, deletes a row and asserts the order and the scroll position.

### Auto-scroll sprite list on selection

> Updated: 2026-02-16 — auto-scroll to selected layer

When a sprite is selected (canvas click, keyboard scroll, or any path through `spriteEdit.setImage()`), the sprite list automatically scrolls to bring the corresponding list item into view via `viewer.gd:scroll_to_selected()`, which calls `ScrollContainer.ensure_control_visible()`. This is a no-op when the item is already visible.

### Physics query vs cached overlap

The mouse cursor uses `PhysicsDirectSpaceState2D.intersect_point()` instead of `Area2D.get_overlapping_areas()` because the latter returns cached results from the previous physics step, creating a one-frame timing mismatch with the cursor position updated in `_process()`.

> Updated: 2026-08-17 — **A layer's collider is one rectangle, and the alpha test decides every hit.** `mouse_cursor._is_pixel_opaque` transforms the click into the sprite's own space, bounds-checks `Sprite2D.get_rect()` and samples the image alpha, so the physics query is only a broad phase producing candidates. The collider therefore only needs to CONTAIN every opaque pixel, and `populate_polygons` builds one `RectangleShape2D` over the image bounds instead of a `CollisionPolygon2D` per traced outline. The traced outlines are still built as `Line2D` children: they are the silhouette drawn around a selected layer and must not change. A `CollisionPolygon2D` decomposes into convex pieces the broadphase re-fits every tick the avatar moves: 36 shapes per layer measured, 45.7 ms/tick across 25 layers against 1.8 ms for one rectangle, which is the floor. Equivalence was checked by running both colliders through the full pick path (query AND alpha test) over every point of a real layer and of an adversarial image (hollow ring, 1px diagonal hair, isolated speck): 65,536 points, identical outcome, nothing gained or lost. The containment direction is also structural, since the rect is the image bounds and the outlines are traced within it, so a click that selects today cannot stop selecting.

> Updated: 2026-08-17 — **The player page runs neither the edit UI nor layer collision.** Both sidebars and every layer row live under `EditControls`, and hiding a node does not stop its `_process`, so the whole edit UI was re-syncing hidden controls 60 times a second behind the player page. `swap_mode()` now sets `EditControls.process_mode` to `PROCESS_MODE_DISABLED` off the edit page (verified: the right sidebar's `_process` ran 0 times in 120 frames on the player page, 120 of 120 on the edit page, and 0 again after switching back). It also calls `set_layer_collision(editMode)`, which toggles every `"saved"` layer's grab shapes through `spriteObject.setCollisionActive()`, because click-to-select is gated on `editMode` and a moving `Area2D` costs the broadphase a re-fitted decomposed polygon every tick regardless. Measured on 25 layers: 23.8 ms/tick live against 2.2 ms disabled. Layers built later inherit the mode through `spriteObject._build_collision()`, the single path that populates shapes. The app starts on the player page (`main._ready()` calls `swapMode()` once), so this is the state it boots into.

> Updated: 2026-08-17 — the layer `Grab` area sets `collision_mask = 0` in `spriteObject.tscn`, and must keep it. The cursor's own `Area2D` carries `collision_mask = 0` for the same reason and `mouse_cursor.gd` names the layer bit in `SELECT_MASK` instead of reading it back off that node: while the cursor's mask matched the layers' bit, the physics server paired the cursor with every layer in the rig every tick, about a third of what the point-query path cost after the layer-vs-layer pairing was removed. A point query matches an area's `collision_layer`, so clearing the mask leaves selection working while telling the physics server this area detects nothing. With the default mask of 1 every layer paired with every other overlapping layer and solved SAT against their traced outline polygons at 60 Hz: measured 198.8 ms/frame for 25 layers versus 16.0 ms cleared, on a 16.1 ms no-pairs floor, and about 43% of a live session's CPU sat in `GodotArea2Pair2D::setup`. `monitoring = false` does not substitute for this; the pair is gated by the *other* area's `monitorable`, which `changeCollision()` drives from costume visibility. `test_performance_memory` guards the mask.

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

Sprites live under `OriginMotion/Origin` in the scene tree. They retain the
`"saved"` group for scene/debugger compatibility and register with
`Global.sprite_nodes()`'s backing registry for production enumeration.

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
> collision-checked ID allocator in `AvatarController`; creating a fresh default-seeded
> generator per layer is no longer allowed.

> Updated: 2026-08-17 — `spriteObject.gd` is a 951-line scene-facing facade,
> down from 1,573 lines at the Phase 12 boundary. Pure talk/blink/costume rules
> live in `sprite_visibility_policy.gd`, and cycle-safe child/descendant lookup
> lives in `sprite_hierarchy.gd`. `sprite_visual_runtime.gd` owns diffuse/normal
> texture synchronization, blend materials/backbuffers, and depth propagation;
> `sprite_collision_runtime.gd` owns shape replacement, monitoring, and edit-page
> activation while `sprite_collision_builder.gd` remains the geometry builder.
> Existing public sprite methods delegate to these boundaries so scene, UI,
> persistence, and undo callers retain their contract.

> Updated: 2026-08-17 — Diffuse replacement synchronizes both `size` and
> `imageSize` before rebuilding textures, wiggle geometry, or collision. This
> prevents an active wiggle mesh and transparent-image fallback collider from
> retaining the previous artwork dimensions. The production runner replaces a
> layer with a differently sized image and verifies the live and broad-phase
> dimensions.

> Updated: 2026-08-17 — Wiggle is split into three layers:
> `wiggle_geometry.gd` is deterministic image/path analysis with no scene state;
> `wiggle_runtime.gd` owns the live appendage, path editor, parameters, and linked
> child attach/release lifecycle; `wiggle_appendage.gd` remains the mesh and
> spring-chain implementation. `spriteObject.gd` supplies authored properties
> and its stable editor facades. Production tests enable and disable a real
> appendage, while pure tests cover width interpolation, root orientation, arc
> projection, silhouette reach, auto-fit coverage, visibility, and hierarchy.

> Updated: 2026-08-06 — Legacy saves without `animClips` migrate their x/y wobble fields into the runtime animation system during shared sprite-state application. Hierarchy changes use `Node.reparent()` consistently. Because reparenting emits `_exit_tree()` / `_enter_tree()` without running `_ready()` again, sprite registry enrollment is owned by `_enter_tree()` and removal by `_exit_tree()`; registration in `_ready()` would permanently lose parented layers from indexed ID lookup.

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
- `begin(gesture)` / `commit()` / `abort()` open one history transaction; an empty gesture is a discrete edit, a named gesture collapses a continuous one

> Updated: 2026-08-06 — `UndoManager` retains history, cache, hierarchy, and
> scene-reconciliation ownership, but delegates sprite property capture and
> application to `SpriteState`. Its former parallel save/restore maps were
> removed. Image caches still hold `Image` references rather than encoding PNGs.

> Updated: 2026-08-17 — **History is transactional and has no interface
> knowledge.** `save_state()`/`save_state_continuous()` are replaced by
> `begin(gesture)` / `commit()` / `abort()`. A command that turns out to change
> nothing calls `abort()`, which pops the snapshot it pushed, so no-op clicks no
> longer leave dead entries the user has to undo through. Continuous edits are
> keyed by **gesture** rather than a single global latch: `_active_gesture` holds
> one key at a time, `end_gesture(name)` ends only that gesture, and a mouse
> release ends whatever is active. Keying by gesture is what makes switching
> controls mid-drag start a new entry instead of silently dropping the second
> control's history, and it lets keyboard-driven edits close their own burst
> (the old latch only reset on a mouse release, so keyboard edits merged
> indefinitely). Restore no longer calls into the sidebars: `_restore()` and
> `_restore_full()` emit **`state_restored(scope)`** and `AvatarController.on_state_restored()`
> owns every scene consequence (`spriteList.updateData` / `refreshHierarchy`,
> `spriteEdit.setImage`, `changeCostume`, `onWindowSizeChange`, the light gizmo).
> Two restore defects were fixed alongside: visibility is re-derived through
> `applyCostumeVisibility()` instead of reading `costumeLayers` directly (the
> direct read ignored `userHidden`, so every eye-hidden layer reappeared on
> undo/redo), and restored sprites reparent synchronously via
> `_link_restored_parents()` instead of relying on `spriteObject`'s deferred
> 0.1s `_ready` timer (which left the hierarchy briefly wrong and leaked a
> `SceneTreeTimer` at exit).

### Mutation Commands (`autoload/domain/mutation_commands.gd`)

The single canonical path for user-initiated mutations that belong in history.
Production code never opens a history transaction directly; a command owns the
before/after snapshot boundary exactly once.

| Command | Use |
|---------|-----|
| `set_layer_property(layer, prop, value)` | discrete single-property edit (toggle, dropdown, spinbox) |
| `drag_layer_property(layer, prop, value, gesture)` | continuous single-property edit (slider drag, held key) |
| `set_layer_field(layer, prop, index, key, value, gesture)` | one key inside a structured field (an `animClips` entry) |
| `structural(body)` | hierarchy, add/remove, costume, image replacement; `body` returns false to discard the entry |
| `drag(gesture, body)` | continuous multi-field gesture (canvas drag, ribbon path editing) |
| `capture_bulk()` | pre-state for work that awaits across frames (avatar load, PSD import) |

- Property writes are validated against `SpriteState`'s persistent field map, so
  a command naming a non-persistent property is reported rather than silently
  failing to survive undo or a save round-trip.
- Unchanged writes return false without touching history, which is what keeps
  re-selecting the current dropdown entry or re-clicking a settled toggle from
  accumulating entries.
- Gesture keys are scoped to layer and property (`_gesture_key`), so the same
  slider on a different layer is a separate entry.
- The history sink is resolved at runtime (`/root/UndoManager`) rather than by
  naming the autoload, so the command layer loads — and is unit-tested against a
  recording sink — in workspaces that register no singletons.

> Updated: 2026-08-17 — Introduced in Phase 14. `tests/unit/test_release_contract.gd`
> enforces that no production file outside this module opens a history
> transaction, so the canonical path cannot quietly regrow a second entrance.

> Updated: 2026-08-17 — **Avatar loads are cancellable.** `load_avatar()` runs
> across frames (worker-pool image decode, then sprite construction), so
> `shutdown()` sets `_load_cancelled` and every suspension point re-checks
> `_load_aborted()`. A cancelled load calls `_abandon_load()`, which releases the
> decode buffers and dismisses the progress dialog, instead of resuming to build
> sprites against a scene that is being torn down. `is_loading()` exposes the
> in-flight state for shutdown paths and the lifecycle gate.

### Save/Load (`saving.gd`, `main.gd`)

- Format: JSON with base64-encoded PNG image data per sprite
- User-facing file extension: `.save`
- PNG encoding for file saves runs on a background thread to avoid stalling the main loop (Updated: 2026-02-16)
- Settings stored separately: volume, sensitivity, window size, background color, costume key bindings, etc.

> Updated: 2026-08-06 — Persistence boundaries are versioned and validated before live scene state is changed. `autoload/persistence/avatar_save_schema.gd` migrates legacy unversioned avatars, supplies typed compatibility defaults, rejects unsupported future versions, duplicate IDs, invalid layers, and hierarchy cycles, and selects sprite entries by their validated shape rather than a fixed metadata allowlist. `settings_schema.gd` owns the complete canonical settings defaults and typed/ranged migration (including legacy NDI ruler-to-crop conversion). `value_codec.gd` is the only persistence-boundary parser for legacy Variant strings. `json_file_store.gd` bounds reads, reports JSON line errors, writes through a same-directory temporary file, and retains/reloads a previous complete `.bak` if replacement is interrupted. Manual saves only update `lastAvatar` after the avatar write succeeds; failed session saves re-arm the dirty flag. The `Saving` singleton remains the compatibility-facing API and exposes `last_error` plus `persistence_error` for actionable UI reporting.

> Updated: 2026-08-06 — Sprite identifiers and their `parentId` / `eyeTrackTargetId` references preserve the complete unsigned 32-bit range produced by Godot's `RandomNumberGenerator.randi()`. Persistence must not narrow these values to signed 32-bit integers before uniqueness and hierarchy validation.

> Updated: 2026-08-06 — Costume membership is serialized as canonical plain Array text (`[0, 1, ...]`). The compatibility decoder also accepts the transient Godot 4.6 typed form (`Array[int]([...])`) written by early schema-normalized builds; disabled slots must never fall back to the all-enabled default during load.

Schema metadata uses `_schemaVersion`; underscore-prefixed root keys are reserved
for avatar-level metadata. A root entry is treated as a layer only when it is a
validated dictionary with `type == "sprite"`. Current schema migration and
atomic round-trip/recovery cases are fixture-tested in
`tests/unit/test_persistence.gd`.

> Updated: 2026-08-17 — Production-scene regression tests supplement the schema
> suite at `tests/integration/avatar_scene_runner.tscn`. A valid 12-layer fixture
> reproduces the previously missed runtime interactions after normalization,
> while a duplicate-ID fixture proves a rejected document leaves the live avatar
> root, instances, and registry untouched. `scripts/run_performance.sh` also
> records full 100- and 250-layer load timings and static-memory observations in
> `.artifacts/performance-avatar-load.json`.

> Updated: 2026-08-17 — **Lifecycle qualification gate.**
> `tests/performance/lifecycle_runner.tscn` measures seven production-scene
> workloads against a 100-layer rig and writes
> `.artifacts/performance-lifecycle.json`: costume switching, hierarchy rebuild
> (full versus refresh-only), sidebar refresh on both pages, command undo memory,
> wiggle tick cost, cancelled-load teardown, and repeated startup/shutdown. Each
> carries a broad smoke ceiling; the JSON numbers are the trend line.
>
> Two measurement rules matter for anyone extending it. First, the runner
> uncaps `Engine.max_fps` for its whole run: headless frames are otherwise paced,
> so a paced wall clock reports the frame interval no matter what the frame did.
> Second, `updateData()` and `refreshHierarchy()` must be awaited. `update_data()`
> yields a frame and then abandons stale generations, so an un-awaited loop
> coalesces into a single rebuild and reports a cost unrelated to rebuilding.
>
> Two claims are established structurally rather than by timing, because per-frame
> cost at this layer count is dominated by the layers themselves. "No hidden edit
> work on the player page" is proved by `can_process()` on both sidebars, not by
> the millisecond difference. Wiggle cost is measured by driving `_update_wiggle`
> directly, after asserting the ribbons built their meshes and advance across
> frames, because a chain's cost could not be separated from frame noise by
> differencing.

> Updated: 2026-08-06 — Save execution is coordinated by
> `main_scenes/controllers/save_controller.gd`. It serializes the scene snapshot
> supplied by `main.gd`, owns both worker threads, joins them on shutdown, and
> keeps manual-save and recovery-copy writes mutually exclusive. The controller
> also owns the native file dialogs and the timestamp policy deciding whether a
> newer `user://session.pngtp` should be offered for recovery.

The versioned field inventory, validation limits, migration rules, and atomic
write behavior are specified in `docs/save_format.md`.

> Updated: 2026-08-06 — Undo snapshots continue sharing immutable `Image`
> references rather than copying or encoding them. The live image/normal caches
> now replace changed references, erase cleared normal maps, and prune IDs no
> longer present in the rig; retained undo/redo snapshots themselves remain the
> only owners needed to restore deleted layers.

### PSD Import (`psd_parser.gd`)

- Runs in background thread with progress reporting
- Supports RGB 8-bit PSD files (version 1, no PSB)
- Extracts layer names, bounds, opacity, channel data
- Import dialog lets user select which layers to add

> Updated: 2026-08-06 — PSD parsing treats the file as untrusted binary input.
> `autoload/import/import_limits.gd` caps file/section sizes, dimensions,
> layers, channels, and total decoded working memory. Every length is checked
> against its enclosing section before a seek/read; PackBits scanline tables
> and exact decoded row widths are validated before native or GDScript decode.
> Parser cancellation is checked between records, channels, rows, and layer
> composition. `main.gd` cancels and joins PSD/APNG workers before it detaches
> from `Global`, and reports worker-start failures without leaving modal UI or
> stale thread references behind.

> Updated: 2026-08-06 — Post-PSD premultiplication and alpha-polygon work uses
> one `WorkerThreadPool` group task with an isolated result slot per layer,
> replacing the previous coordinator that created one OS thread per selected
> layer. Avatar-load pool ownership is tracked too, and both groups are joined
> before main-scene teardown.

### Unified Replace (`replace_review_dialog.gd`)

> Updated: 2026-02-28 — Added unified Replace flow

> Updated: 2026-08-17 — **Folder replace is unreachable.** The Replace dialog is
> a `FileDialog` in `FILE_MODE_OPEN_FILE` filtered to `*.psd` and `*.png`, so a
> folder can never be selected and `_on_replace_file_selected()` only ever
> dispatches to the PSD or single-PNG handler. `_handle_replace_from_folder()`
> and `_show_replace_review_from_items()` are complete and correct but have no
> caller. The Phase 16 audit left the implementation in place rather than
> deleting a documented feature: re-exposing it needs a directory dialog (or
> `FILE_MODE_OPEN_ANY`) and is a product decision, not a refactor.

- Uses a `FileDialog` in `FILE_MODE_OPEN_FILE` with `*.psd` and `*.png` filters
- **PSD replace**: Parses PSD (reuses PSD parser thread), matches layer names to existing sprite names (case-insensitive), shows review dialog
- **Folder replace**: implemented in `_handle_replace_from_folder()` but **not currently reachable** — the Replace dialog only accepts a single PSD or PNG file, so nothing dispatches to it (see the 2026-08-17 note below)
- **Single PNG replace**: If a sprite is selected, replaces that sprite directly (preserves APNG detection)
- Review dialog shows matched sprites (will be replaced), new items (checkboxes to optionally add), orphaned sprites (option to remove)
- Name matching: `psd://Name` → `Name`, `/path/file.png` → `file`, case-insensitive via `.to_lower()`
- `spriteObject.replaceSpriteFromData()` replaces image data in-place, preserving all properties (position, physics, costumes, parent-child, etc.)
- All operations are fully undoable via `MutationCommands.capture_bulk()`

### APNG Import (`apng_parser.gd`)

- Detects animated PNGs by checking for `acTL` chunk
- Composes frames into horizontal sprite sheet
- Calculates animation speed from frame delays
- Caps at max texture width (16384px)

> Updated: 2026-08-06 — APNG detection and parsing validate signature, chunk
> bounds, CRCs, IHDR/acTL/fcTL shapes, canvas/frame geometry, operation values,
> declared frame count, compressed-byte accumulation, and total decoded frame
> memory. Composition uses Godot's bounded image blit/blend operations and the
> parser supports cooperative cancellation. Integration tests exercise both a
> generated valid animation and malformed/truncated inputs.

### Stream Deck Integration

> Updated: 2026-08-06 — The Stream Deck autoload remains dormant unless its
> setting is enabled and a valid platform config/port is available. The local
> bridge URL is an explicit `ws://127.0.0.1` endpoint. `protocol.gd` validates
> JSON packet/event/action/payload shapes and project-local scene paths before
> the singleton emits input or changes scenes. Invalid packets do not interrupt
> processing of later queued packets, and the websocket is closed explicitly
> during shutdown. Linux, which has no configured plugin path, now degrades
> without dereferencing a missing file.

---

## Input Handling

> Updated: 2026-08-17 — **The z-index overlay is a component, not singleton
> state.** `ui_scenes/zIndex/z_index_editor.gd` (a `Node2D` added under `main` on
> first use) owns the panel construction, styling, confirm-flash tween, and the
> click-outside hit test. `Global` keeps only what input routing needs:
> `is_z_index_editor_active()`, `_show_z_input()`, and `_hide_z_input()`. The
> editor commits through `MutationCommands`, so an entered depth is one undoable
> command and re-entering the current value adds no history.
> `Global.detach_main()` drops the reference because the component lives under
> the scene it was created in.


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

> Updated: 2026-08-17 — **One input command decoder.**
> `autoload/input/input_commands.gd` holds the key/device rules as data and
> decodes them purely: no engine polling, no scene access. `FOREGROUND` maps each
> polled action to a command plus its guards (selection, edit mode, control
> modifier, text focus, open file dialog), and `FOREGROUND_ORDER` fixes dispatch
> order. `Global._run_key_commands()` builds the guard snapshot and runs whatever
> the decoder returns; `Global._run_key_command()` is the only place the effects
> live. Background capture (the optional OS-level hook) and Stream Deck costume
> keys route through `decode_background()`, `decode_visibility_capture()`, and
> `decode_device_costume()` in `main.gd`, replacing three separate inline
> decoders. Stateful, timing-based interactions stay in `Global` where they
> belong: the origin tap-versus-hold threshold, ribbon-path escape, and the
> mode-clearing fallbacks are not command decodes. Focus guards and Stream Deck
> behavior are unchanged; `Global.is_awaiting_animation_key_capture()` was added
> so the decoder can tell an armed animation bind from a live trigger.

> Updated: 2026-08-06 — The view-mode volume and sensitivity sliders now write
> `Global`/settings from `value_changed`; they no longer rewrite unchanged
> values every frame. Layer-list hierarchy builds use direct sprite-to-row maps
> rather than nested parent searches, and row badges only write Control
> properties when their underlying state changes. Sprites with no animation
> clips bypass animator allocation/evaluation and unchanged talk/blink visual
> state bypasses repeated CanvasItem writes.
| Middle drag| Pan viewport                              |
| Ctrl+K     | Tap: screenshot; Hold (≥1s): record transparent video. Format (WebM/APNG/GIF) and FPS (15/30/60) configurable in Settings. APNG/GIF default to 15 FPS, WebM defaults to 30 FPS. When NDI is enabled, captures the NDI crop view (auto-framed avatar) instead of the main camera view (updated 2026-03-12) |
| Left click | Select sprite / deselect on empty space   |

---

## Signals

Key signals defined in `global.gd`:

- `startSpeaking` / `stopSpeaking` — mic threshold crossed
- `pressedKey` — keyboard input forwarded for toggle bindings
- `visibility_binding_armed` — sprite visibility toggle await trigger

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
| `ndi/ndi_output_geometry.gd` | Pure validation, output-size clamp, aspect ratio, center, and zoom calculation |
| `ndi/ndi_crop_box.gd` | Resizable dashed-orange crop box with 8 gizmos, drawn in edit mode |

### Framing (manual crop box)

> Updated: 2026-06-12 — **The auto-framing is gone.** The old system computed a union bounding box of per-sprite envelopes (texture opaque rects grown by wobble/rotation/eye-track/wiggle margins) above a draggable horizontal crop line. Estimating every motion system's reach (wiggle chains, drag lag, rotational drag, animation clips...) proved impractical — margins were always too tight somewhere and too generous elsewhere — so the user now draws the frame directly. `_compute_sprite_envelope()`, `_get_opaque_rect_local()`, `_rotation_expanded_aabb()`, `_get_rest_position()`, `spriteObject.wiggle_bounds_local()`, and `ndi/ndi_ruler.gd` were removed.

1. The frame is the user-drawn **crop box**: origin-relative edges `[left, top, right, bottom]` in `Saving.settings["ndiCropRect"]`, placed at the avatar's **rest** position (`rest_origin_pos` = `origin.global_position − OriginMotion bounce offset`). The camera is static between recalcs, so the avatar visibly bounces *within* a fixed frame.
2. **One-to-one with the output (2026-06-13).** The rendered rectangle equals the drawn box exactly on all four edges. The earlier per-edge bounce/wobble headroom on the bottom (`bottom_margin = ref_y_amp + ref_eye + peak_displacement`) was removed: the crop now ships pre-configured per avatar, so it's WYSIWYG and whoever sets it up bakes any desired margin into the box itself (same as the top and sides). Consequence: an up-bounce can bring content below the box's bottom edge into the bottom of the frame, so a bouncing avatar's box should leave a little bottom headroom. This made the `ndiRefLayer` flag, the Neck/Body auto-detect, and the `peak_displacement` math **inert for framing** (the flag/UI/persistence still exist; pending a decision to remove them).
3. Viewport sizing: user picks width preset (512/720/1080/1920), height computed from the box's aspect ratio (auto mode) or user-set with letterbox fit (manual mode). Camera centered on the box.
4. Recalculation only when dirty flag set (avatar load, box edit, settings change; debounced 1 s). The edit-mode box (`ndi_crop_box.gd`) also anchors to `rest_origin_pos` so the on-canvas rectangle matches the output 1:1 even while the avatar bounces (it previously rode the live origin).

### NDI Crop Box

A dashed orange rectangle (`ndi/ndi_crop_box.gd`, owned by the NDI manager,
visibility layer 2) is visible in edit mode when NDI is enabled — same look as
the old crop line. Resize via 8 constant-screen-size gizmos: 4 edge midpoints
(move that edge, H/V resize cursors) and 4 corners (move both adjacent edges,
diagonal cursors). Grabbing a **bare edge line** (away from any gizmo) returns
`H_MOVE` and translates the whole box without resizing (move cursor), so you can
reposition the frame by dragging any side. Minimum box size 64 px; sidebars
block grabs (same screen-space guard as before). While dragging, bounce/wobble
freeze at worst-case-down via `ndi_manager.crop_dragging` (checked in
`main._process` and `spriteObject.wobble`).

> Per-avatar persistence (kept from the crop line, 2026-06-12): `_build_avatar_save_data()` writes `"_ndiCropRect"` ([l, t, r, b]) to the avatar JSON (alongside `"_light"` / `"_eyeTrackingGloballyEnabled"`), plus legacy `"_ndiRulerY"` (= box bottom) so older builds still pre-frame. `load_avatar_file()` restores `_ndiCropRect`; a legacy save with only `_ndiRulerY` keeps the current box and snaps its bottom to the line. Saves with neither key keep the current crop. Settings migration: `_load_settings()` seeds `ndiCropRect` from an old `ndiRulerY` (line Y becomes box bottom). Box edits are intentionally non-undoable (not in UndoManager snapshots).

### Settings (`Saving.settings`)

- `ndiEnabled` (bool) — toggle NDI output
- `ndiWidth` (int) — output width preset
- `ndiMode` (string) — "auto" or "manual"
- `ndiManualWidth` / `ndiManualHeight` (int) — manual resolution
- `ndiCropRect` (Array [l, t, r, b]) — crop box edges, origin-relative (replaced `ndiRulerY`, 2026-06-12)

### Graceful Degradation

Uses `ClassDB.class_exists("NDIOutput")` before instantiation. If the godot-ndi plugin is not installed, the NDI settings section shows "plugin not installed" and disables the toggle. The app never crashes from a missing plugin.

> Updated: 2026-08-06 — Missing native support also clears a stale persisted
> enable flag. Output dimensions, modes, and crop rectangles are normalized at
> the manager boundary as well as by the settings schema. The manager guards
> deferred dirty calls and unavailable main viewports, disconnects the root
> resize signal, stops its timer, and synchronously releases `NDIOutput` before
> its viewport during application teardown.

> Updated: 2026-08-06 — `NDIOutputManager` owns the crop box as its child rather
> than attaching it to `Global.main`. Immediate tree shutdown releases only the
> native `NDIOutput` eagerly and leaves scene-owned viewport/crop containers to
> Godot's recursive teardown, avoiding double-lifetime work.

### Plugin Dependency

Requires the godot-ndi GDExtension plugin (by unvermuthet, MPL-2.0) in `addons/godot-ndi/`. Also requires NDI Runtime installed on the user's OS.

> Updated: 2026-08-06 — The macOS v1.2.6 binaries carry the documented MPL
> patch in `addons/godot-ndi/patches/`. `ViewportTextureRouter` is quiesced at
> scene deinitialization, so `frame_post_draw` disconnects while
> `RenderingServer` is valid; the router remains alive through rendering cleanup
> to absorb queued texture callbacks, then is deleted at core deinitialization.
> `scripts/run_ndi_teardown_smoke.sh` covers idle extension and rendered active
> output shutdown on macOS hosts with the NDI runtime installed.

> Updated: 2026-08-17 — The active-output smoke renders 120 frames before
> requesting shutdown. Three frames intermittently quit Godot 4.6.3 while its
> Metal `compiler reply queue` still owned a shader-cache callback; macOS crash
> reports faulted in `RenderingDeviceDriverMetal::shader_cache_free_entry`, not
> the extension. Allowing pipeline initialization to settle keeps the smoke
> focused on the NDI scene/core teardown it is designed to validate; five
> consecutive idle/active repetitions pass on the pinned engine.

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

- **Sprite Edit Panel** (`normal_map_panel.gd`, wired by `sprite_viewer.gd`): status label, Import button (opens file dialog), Clear button
- **Sprite List** (`sprite_list_object.gd`): Blue "N" badge shown next to layer name when normal map is assigned

## Light Compatibility Data

> Updated: 2026-08-06 — The light gizmo is dormant and is not part of the
> production scene or release manifest. Normal-map rendering remains supported,
> but there is no active light-placement UI. The guarded hooks and normalized
> `_light` avatar metadata remain solely to avoid discarding older save data;
> they must not be described as an active runtime system until a tracked,
> tested scene component is restored.

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

1. **`effects/wiggle/wiggle_appendage.gd`** (`WiggleAppendage2D extends Polygon2D`) — a decoupled port of the remix's angular-momentum spring chain: each joint is a torsional spring toward the previous joint's angle (+ curvature) with momentum, **linear damping**, a hard `max_angle` limit + `comeback_speed` spring, and gravity droop. The root point follows the node's `global_position` (so avatar bounce/drag/wobble propagate in as momentum → the whip), and `auto_wag` adds a **sinusoidal sway to the root direction** — the chain follows it with spring lag, so the base moves smoothly (clean sine) and the tip whips. Propagation smoothness is governed by `max_angular_momentum` (per-joint rotation-speed cap) and `stiffness_decay` (joints soften toward the tip), both scaled from stiffness in `_wiggle_params`. Output is a deformable triangle-strip mesh; `joints_local()` / `rest_joints_local()` expose the live and rest chain joints for child-follow. No anchor/mirror/`actor` coupling, and the original's brake-on-reversal damping was replaced with linear damping (it caused a rotate-stop-rotate stutter at wag reversals).
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

> Updated: 2026-09-15 — **Children keep their offset from the spine (they used to snap onto it).** The old follow projected the child's rest position onto `smooth_path`, then wrote `child.position = appendage.sample_local(fraction)`. The sideways distance was never stored or restored, so a child attached beside the spine (an earring on an ear, a bow on a tail) jumped onto the centerline the moment wiggle turned on, and one past either end snapped to that end. Two smaller mismatches added to it: the projection ran on the smoothed path while the sample ran on the coarse physics chain (chords cut inside a curve, worse at low **Bones**), and `WiggleGeometry.tangent` read the arc-length fraction as a point index, so the rest and current angles disagreed even at rest. Now `WiggleRuntime.apply_to_children()` binds each child **rigidly to one chain segment** via the pure pair `WiggleGeometry.bind_to_chain()` / `follow_chain()`: which segment, how far along it, and the child's offset in that segment's own frame. Binding runs against `appendage.rest_joints_local()` (the chain's own rest, laid out exactly as `reset()` does), so an at-rest chain reproduces the authored position to floating-point exactness; `_bind_serial` (bumped by `rebuild_chain()` and `sync_to_offset()`) rebinds after a geometry or anchor change. Because the follow overwrites `position` every frame, the authored position now lives in `_wiggleRestPos` and is reached through **`spriteObject.authoredPosition()` / `setAuthoredPosition()`**, which `moveSprite`, `moveOrigin`, `snapOriginToMouse`, the origin-gizmo drag, `SpriteState.capture_properties` / `apply_existing`, and layer duplication all use. Previously a save or undo snapshot taken while wiggle was on stored the snapped position permanently, and dragging a following child was undone on the next frame.

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

> Updated: 2026-06-10 — Per-layer keyframe/transform animations. A layer holds a list of **animation clips** (`spriteObject.animClips`, an Array of Dictionaries) evaluated each frame by `effects/animation/layer_animator.gd` (`LayerAnimator`, RefCounted). Two **shapes** — `twitch` (one-shot half-sine ease out-and-back) and `oscillate` (continuous sine) — on two **channels** — `rotation` (degrees) and `translation` (pixels). Four **triggers**: `always` (idle; oscillate runs continuously, twitch loops), `random` (blink-style per-frame probability `randi() % chance`), `key` (a bound key via the optional `BackgroundInputCapture`, with foreground input retained when absent), `manual` (the Test button). Designed extensible: new shapes/channels/triggers are added in one place each.

### Composition — where it applies
`LayerAnimator.evaluate(clips, tick, delta)` sums every clip into `rot` (radians) + `trans` (px), read each frame in `spriteObject._process` as `_animRot` / `_animTrans`. **Rotation rides `dragOrigin.rotation`** — the outermost transform on the layer — so it rotates the visible `Sprite2D` AND (for wiggle layers, where the Sprite2D is hidden) the deformable mesh + chain anchor, driving the verlet chain into secondary motion (a twitch whips a wiggly ear). It composes *outside* `sprite.rotation = _micRot + _eyeTrackRotation` (mic sway + eye-track stay inner). **Translation feeds `wob.position`** in `wobble()` (the base, before the eye-track offset is added) — exactly where the legacy wobble wrote. Suppressed while tracing a wiggle path (`_wigglePathEditor != null`).

### Legacy wobble migration
The old free-running wobble (`xFrq/xAmp/yFrq/yAmp`, a free sine on `wob.position`) is subsumed: it maps 1:1 to an `always`/`oscillate`/`translation` clip carrying `ampX/freqX/ampY/freqY` (identical `sin(tick*freq)*amp` math, so migrated avatars look pixel-identical). On load, when a save has **no `animClips` key**, `spriteObject.migrateLegacyWobble()` folds nonzero wobble into such a clip; the legacy fields are left intact (older app builds still read them) and `wobble()` no longer reads them. New saves carry `animClips` and skip migration. **Only the wobble migrated** — the bounce-reactive rotation (`rdragStr` / `rLimitMin/Max`), squash (`stretchAmount`), and drag-lag (`dragSpeed`) remain physics (now under the left sidebar's **Reactive** tab), NOT animations.

### UI — left sidebar tabs
`sprite_viewer.gd` gained a `SidebarTabBar` (reused from the right sidebar) below the sprite-sheet section: **Animation** and **Reactive**. Preview / Position / Normal-map / sprite-sheet frames+speed stay always-visible above the tabs. **Animation** content is built by `ui_scenes/spriteEditMenu/animation_clip_panel.gd` (`AnimationClipPanel`, RefCounted): a clip **list** with **+ New** / **Remove**, and an **inspector** for the selected clip (name, channel, shape, motion params, trigger → chance slider *or* Bind-key button, **▶ Test**). It rebuilds on a structural signature change (sprite / clip count / selection / channel / shape / trigger) and otherwise only refreshes live values (so undo of a slider edit shows without rebuilding mid-drag). **Reactive** holds drag / rotational-drag + limits / squash. `_layout_panel()` lays out the header sections, the tab strip, then the active tab's sections (re-run on tab switch, freeing prior dividers first); the active tab persists in `Saving.settings["leftSidebarTab"]`.

### Triggers (keys) & persistence
Key binding mirrors the costume-hotkey flow: the inspector passes its live clip
dictionary through `Global.begin_animation_key_capture()`; `main.gd` gives the
next captured key to `apply_animation_key_capture()`. At runtime that handler
enumerates `Global.sprite_nodes()` and calls
`spriteObject.triggerAnimationKey(key)`, guarded by
`Global.has_text_entry_focus()` and the costume-bind state so it does not fire
while typing or binding. `animClips` persists as **one field** via `var_to_str` /
`str_to_var` across all sites — `main.gd` save / load / duplicate and
`undo_manager.gd` snapshot / `_restore` / `_add_sprite_from_data` — deep-copied
(`.duplicate(true)`) in dup + undo so snapshots do not alias the live array.

### Curves & preview graph
> Updated: 2026-06-10 — A twitch clip carries a **`curve`** field selecting its easing envelope from `LayerAnimator.envelope(curve, ph)` (a `static func`, the single source of truth): `smooth` (half-sine), `ease` (rounded plateau), `snap` (fast attack/slow release), `spring` (overshoot + damped bounce through rest), `pulse` (linear triangle). The runtime (`_eval_twitch`) and the inspector preview both call it, so the preview is exact. Append-only (add a `match` case + a `_CURVES`/`_CURVE_LABELS` entry). The animator tracks live per-clip state in `_rt[i]` (`active` + normalized `ph`) for **both** shapes (twitch: progress 0→1; oscillate: phase within one period) and exposes it via `LayerAnimator.sample(i)` → `spriteObject.getAnimSample(i)`. The inspector adds a **Curve** dropdown (twitch only) and an `AnimationCurveGraph` (`ui_scenes/spriteEditMenu/animation_curve_graph.gd`, `Control` + `_draw`): it plots the curve (value vs normalized time) and a **dot that rides it** whenever the clip plays — Test or organic trigger — by polling `getAnimSample` each frame (only while `is_visible_in_tree()`, so the hidden Reactive tab costs nothing). `curve` rides in `animClips` (no new persistence sites) and is part of the inspector's structural signature so changing it rebuilds the preview.
