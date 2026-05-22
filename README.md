# PixelLab Studio

A modern, opinionated PNGTuber avatar engine. PixelLab Studio takes the familiar
two-frame talking-avatar workflow and extends it with per-layer physics,
parent-child layer hierarchies, eye tracking, native NDI broadcast, recording
with a transparent background, normal-map lighting, and a comprehensive
non-destructive editor — all built on Godot 4.

## What it is

PixelLab Studio renders a layered, physically reactive avatar in real time from
PNG, multi-frame PNG sprite sheets, or PSD files. It's designed to look great
both in stream overlays and in standalone clips, and to give a serious
content creator the control they'd expect from a dedicated character rig
without writing a single line of code.

## What it can do that PNGTuber Plus (the original) can't

PNGTuber Plus is a fantastic starting point — PixelLab Studio is what happens
when you keep extending it. Beyond the original feature set, PixelLab Studio
adds:

- **Native NDI broadcast.** Send the avatar directly to OBS (or any NDI
  receiver) as a network video source with transparent alpha. No chroma key,
  no screen capture, no second window — OBS sees the avatar as a clean NDI
  source.
- **Recording with transparent background.** Capture loops of the avatar to
  WebM (VP9 alpha), animated PNG, or animated GIF — all with true
  transparency suitable for re-use in video editors.
- **Per-layer wobble physics.** Each layer has independent X/Y frequency and
  amplitude wobble, drag (follow-with-lag), squash/stretch, and rotational
  drag — none of this is global. A scarf flutters differently from a hat.
- **Rotational limits.** Clamp how far a sprite can rotate so heads don't
  spin past believable angles.
- **Eye tracking with two modes.** Eyes can follow the cursor in screen
  space, or follow another layer in the rig (whip-pick the target with a
  visual link line). Per-layer enable, global kill switch, invert direction,
  configurable distance and speed.
- **Layer parenting.** Build a real rig — earrings parented to the head,
  the head parented to the body. Children inherit transforms and physics
  contributions from their parent.
- **Static elements.** Mark a layer as static so it ignores avatar-wide
  bounce — useful for backdrops, anchors, or stable accessories — while it
  still receives drag, wobble, and rotation.
- **Clip-linked sprites.** Constrain a layer's render to the bounding shape
  of its parent — clean masking without writing a shader.
- **Visibility-toggle key bindings.** Bind any keyboard key to show/hide a
  specific layer for quick prop toggles mid-stream.
- **Costume system.** Switch between 10 costume states via hotkeys (`1`-`0`
  by default), with per-layer rules for which costume slots each layer
  participates in.
- **Multi-frame sprites and per-layer animation.** Any layer can have its
  own sprite-sheet frames and a configurable animation speed independent of
  the rest of the rig.
- **Normal-map support.** Pair a `_NRML`-suffixed PNG with any diffuse
  layer on import for proper lighting response (Light2D control coming soon
  — see Roadmap).
- **PSD import preserving layer structure.** Drop a PSD in and it lands as
  a fully parented rig with each Photoshop layer as a separate sprite,
  retaining position, layer order, and group hierarchy.
- **Undo/redo across everything.** Sliders, checkboxes, layer moves,
  imports, deletes — the entire edit session is reversible.
- **Resizable, persistent sidebars.** Drag either sidebar's edge to resize.
  Widths are saved with your settings and restored on next launch.
- **Auto-restore last avatar.** The most recently saved or loaded avatar
  re-opens automatically on startup; an empty canvas is shown only if the
  file is missing.
- **Screenshot with transparent background.** `Ctrl+K` grabs the current
  frame as a transparent PNG, suitable for thumbnails or animated overlays.

## Who it's for

- **VTubers and streamers** who want a more expressive avatar than the
  basic two-frame talking head — without having to learn rigging in
  Live2D or VRoid.
- **Content creators producing static or animated assets** — the
  transparent-background recording and screenshot exporters let you reuse
  avatar moments in video editors, social posts, and thumbnails.
- **OBS users who use NDI** — direct NDI output is the cleanest possible
  pipeline into OBS Studio, vMix, or any NDI-aware switcher; no screen
  capture, no chroma key, full alpha.
- **Anyone with a multi-layered Photoshop file of their character** who
  wants to bring it to life with one PSD drop and a few sliders.

## GUI design

PixelLab Studio is built around three persistent regions:

1. **Top menu bar.** Exit, Import, Duplicate, Replace, Save, Load, Clear,
   Reset — global file and project actions, always available.
2. **Left sidebar (edit mode only).** All per-layer controls for the
   currently selected sprite. From top to bottom:
   - Sprite preview thumbnail
   - Normal-map import/clear
   - Position, offset, parent, layer info (read-only)
   - Animation: frames + speed
   - Drag (follow-with-lag amount)
   - Rotation: squash + rotational drag
   - Per-layer toggles: ignore bounce, clip linked sprites, static element,
     NDI reference layer
   - Wobble: X frequency/amplitude, Y frequency/amplitude
   - Rotational limits: min/max rotation + a live rotation gauge
3. **Right sidebar (always visible).** Avatar-wide controls.
   - Top action row: speaking/blinking preview, link, unlink, trash
   - Layer search/filter
   - Layer list (drag-and-drop reorderable, collapsible by parent)
   - User-draggable split between the layer list and the controls below
   - Costume buttons (10 quick-switch icons)
   - Eye tracking: enable, invert, mode dropdown (Cursor / Layer), pick
     target button (whip-pick), tracking distance, tracking speed
   - Visibility toggle: bind a key to show/hide the selected layer

Every control follows a uniform spacing model (a single `ROW_GAP` value
between adjacent widgets, with dedicated `DIVIDER_PAD` padding around
section dividers). The sidebars are screen-space (CanvasLayer), so they stay
nailed to the viewport edges regardless of camera zoom or pan in the canvas.

The bottom-right corner shows controls for non-edit mode (mic, settings,
edit toggle, volume/sensitivity meters), plus zoom and version info.

## Getting started

### 1. Download and launch

1. Download the latest release for your platform from the Releases page.
   - **macOS**: a `.dmg` containing `PixelLab Studio.app`. Drag it to your
     Applications folder.
   - **Windows**: a `.zip` containing `PixelLab Studio.exe` and its
     supporting files. Extract anywhere.
2. Launch the app. On first run macOS may show a Gatekeeper warning —
   right-click the app and choose Open, then confirm.
3. The first launch opens an empty canvas. Use Import or Load from the top
   menu to bring a character in.

### 2. Loading an avatar

Three ways to bring a character in:

- **Import a PSD.** `Import` from the top menu, choose a `.psd`. Each
  Photoshop layer becomes a sprite, group structure becomes parent
  relationships, and the rig is laid out around the world origin. Layers
  ending in `_NRML` (case-insensitive) auto-pair as normal maps for their
  matching diffuse layer.
- **Import PNG sprite sheets.** `Import` accepts multiple PNGs. Frame count
  (horizontal sprite sheet) and layer order are configured per sprite once
  it's in the scene.
- **Load a saved rig.** `Load` opens a previously saved `.save` file. The
  most recent save is re-loaded automatically next time you launch the
  app.

Save your project anytime with `Save`. A progress bar appears while images
encode, then a confirmation toast appears on completion. Saves land in your
platform's user data directory by default; you can navigate anywhere from
the native file picker.

### 3. Editing the rig

Click any sprite on the canvas to select it; its controls populate the left
sidebar. Right-click a slider to reset that property to its default. The
selected layer also highlights in the right sidebar's layer list.

To set the rest origin of a sprite (the point it pivots around when
rotating), enter origin mode and drag the white dot on the selected sprite
to where its pivot should be.

To parent a layer to another, click the Link button at the top of the right
sidebar and connect the child to its desired parent. Eye-tracking layer
mode uses a similar whip-pick from the Pick button next to the eye-tracking
mode dropdown.

### 4. Sending the avatar to OBS via NDI

PixelLab Studio publishes the avatar as an NDI source with a transparent
background — no chroma key, no screen capture.

1. Open the settings menu (gear icon, bottom-right). Enable **NDI Output**.
2. Optionally set the **NDI source name** (this is what OBS will see).
3. In OBS Studio, install the official obs-ndi plugin (DistroAV) if you
   haven't already.
4. Add a new source → **NDI Source**, then pick `PixelLab Studio` (or your
   custom name) from the dropdown.
5. The avatar appears in OBS with a transparent background; layer it on top
   of whatever you like.

A draggable orange dashed line on the canvas marks the bottom crop boundary
for the NDI frame — drag it up to crop tighter (e.g., framing for a
talking-head shot). The NDI output dynamically reframes to fit the rig.

## Features in detail

### Animation and physics

- **Talk / blink frames.** Each layer's `showOnTalk` and `showOnBlink`
  values determine which frame is displayed during talk/blink states.
  Frame 0 is the rest pose; subsequent frames cycle automatically based on
  the layer's animation speed.
- **Per-layer sprite-sheet animation.** Set frames > 1 and a speed and
  the layer cycles through its sprite sheet. Useful for breathing
  effects, fluttering hair, animated mouths, or magical sparkles.
- **Wobble.** Independent X and Y sine-wave oscillation, each with its
  own frequency and amplitude. Combine them for figure-eight motion,
  bobbing, or jiggle.
- **Drag.** A lerped follow-with-lag offset that makes large layers
  trail behind smaller ones during bounce — feels physical without
  being a real spring simulation.
- **Squash and stretch.** Driven by the layer's vertical velocity —
  the avatar elongates as it falls back from a bounce and squashes
  on contact, scaling by a tunable amount.
- **Rotational drag.** As the layer moves vertically, rotational drag
  rotates it slightly into the direction of motion (head tilts back
  on a bounce, returns to rest on the way down).
- **Rotational limits.** A min/max angle clamp prevents over-rotation.
  Min and max are independent and visualized on a live rotation gauge
  in the editor.

### Layer system

- **Parent-child hierarchy.** Layers can be nested. Children inherit
  position, rotation, drag, and bounce from their parent.
- **Drag-and-drop reordering.** Reorder sprites in the layer list to
  change z-index; drag onto another layer's drop zone to reparent.
- **Filter.** Type in the filter field to quickly find a sprite by name
  in deep rigs.
- **Static elements.** Ignore the avatar's bouncing while still
  receiving wobble, drag, and rotation.
- **Clip linked sprites.** Render a child only inside the visual
  bounds of its parent.
- **NDI reference layer.** Mark one layer as the NDI framing reference
  so the broadcast frame anchors consistently regardless of which
  layer is currently in motion.

### Eye tracking

- **Cursor mode.** Eyes follow the OS mouse cursor.
- **Layer mode.** Eyes follow another sprite in the rig. Whip-pick the
  target by clicking Pick and dragging the line to the target layer in
  the canvas or the layer list.
- **Per-layer enable.** Each "eye" layer has its own toggle.
- **Global kill switch.** Disable all eye tracking with one click when
  the toggle is in global scope (no layer selected).
- **Invert direction.** Flip the tracking direction (eyes look away
  from the target instead of at it).
- **Tracking distance and speed.** Independent per layer.

### Costume system

- 10 costume slots, switchable via hotkeys `1` through `0` (configurable
  in settings).
- Each layer can specify which slots it appears in; layers can be in
  one slot, multiple slots, or all slots.
- An optional "bounce on costume change" setting adds a satisfying
  hop when switching costumes.

### Visibility toggles

Bind any key to show/hide a specific layer for ad-hoc props mid-stream
(a sign that pops up when you read chat, a celebration confetti layer
on bits, etc.). The binding is per-layer, stored with the avatar save
file.

### Lighting (normal maps)

Normal maps are a property of a diffuse layer, not separate layers.
Either drop a `_NRML`-suffixed PNG/PSD layer next to its diffuse pair
on import (auto-pairs case-insensitively), or use the **Normal** button
in the left sidebar to attach a normal map manually. The textures are
paired via `CanvasTexture` so they render together with lighting
response.

### NDI output

- Dynamic framing based on the avatar's silhouette plus a user-defined
  bottom crop line.
- Configurable output width (auto or manual width/height).
- Source name override (what OBS sees in the NDI source list).
- Renders on its own SubViewport — completely separate from what you
  see in the editor, so editing UI overlays don't appear in OBS.
- Available on macOS (universal binary), Windows (x64), and Linux
  (x64 and ARM64).

### Recording

- **WebM (VP9 with alpha)** for high-quality, fully transparent video
  re-usable in any video editor.
- **APNG** for animated images with full alpha.
- **GIF** with one-bit alpha (palette-quantized).
- Configurable frame rate per recording.
- Records to the NDI crop view when NDI is enabled so what you get is
  what your viewers see; otherwise records the full canvas.

### Screenshot

- `Ctrl+K` captures the current frame with a transparent background
  to a `.png` of your choice. Like the recorder, respects NDI cropping
  when NDI is enabled.

### Persistence and recovery

- All settings (volume, microphone, NDI options, sidebar widths,
  background color, blink chance, etc.) are saved to the user data
  directory and restored on next launch.
- The most recently opened or saved avatar is auto-restored at startup;
  if the file is missing or fails to parse, the app starts on an empty
  canvas instead of erroring out.
- Save/load uses native OS file pickers (Finder on macOS, Explorer on
  Windows), defaulting to the user data directory for first-time saves.

### Editor ergonomics

- **Right-click any slider** to reset that property to its default
  value.
- **Drag the right edge of the left sidebar** (or the left edge of the
  right sidebar) to resize. Widths persist across sessions.
- **Drag the divider between the layer list and the costume row** to
  resize either area.
- **Wheel scroll** the left sidebar to reach long sections when the
  window is short.
- **Click the eye-tracking dropdown's label** to see the full target
  name in a hover tooltip when the name is truncated.
- The whole UI lives on a CanvasLayer, so camera pan and zoom in the
  canvas never disturb the editor layout.
- During a window-resize gesture, the avatar's physics are frozen so
  sprites don't stretch or jitter as the viewport changes.

### Microphone and voice activation

- Per-device selection (any input device the OS exposes).
- Volume and sensitivity sliders with real-time meter feedback.
- Right-click the mic icon to mute the input entirely.
- A `release duration` setting controls how long the avatar continues
  the talking pose after voice drops below threshold (prevents
  flickering on natural pauses).

### Background and window

- Custom background color (including transparent, for stream overlay
  setups not using NDI).
- Transparent window option for compositing the avatar directly on
  a desktop layer.
- Configurable max FPS (default 60).
- Configurable window size and a remembered last-window state.

### Stream Deck integration

PixelLab Studio ships with the Elgato Stream Deck addon for
hardware-button-driven costume changes, visibility toggles, mic mute,
and other live actions. Settings exposed in the settings menu.

## Roadmap

The following are planned but not yet shipped — pull requests welcome:

- **Light2D-based dynamic lighting controls.** Currently the renderer
  reads paired normal maps; a UI for placing, coloring, and animating
  lights is the next step.
- **Right-sidebar tab system.** Eye Tracking / Lighting / Details tabs
  to consolidate the bottom half of the right sidebar and move the
  normal-map controls and per-layer detail toggles over from the left
  sidebar.
- **Settings dialog audit.** Same uniform spacing model applied to the
  sidebars, applied to the settings dialog.
- **Theme consolidation.** Project-level theme resource so the slider,
  checkbox, and button styling can be tuned in one place rather than
  scattered across scenes.

## Tech notes

- Built with **Godot 4.6** (GL Compatibility renderer for broad GPU
  support).
- Native GDExtensions for NDI output (`godot-ndi`), PSD parsing
  (`psd-native`), and Stream Deck (`godot-streamdeck-addon`).
- macOS universal binary (Intel + Apple Silicon), Windows x64, Linux
  x64/ARM64.
- All UI on a single `CanvasLayer` (`UILayer`) for camera-independent
  screen-space rendering.

## Contributing

Bug reports, feature requests, and pull requests are welcome on the
project's issue tracker. If you're contributing UI work, the project's
architecture guide (`docs/architecture_guide.md`) documents the layout
conventions, spacing model, and resize/persistence patterns to follow.

## License

See `LICENSE` for the project's license.
