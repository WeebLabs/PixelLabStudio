# PixelLab Studio

A 2D PNG avatar program for streamers and content creators. PixelLab Studio
started as a fork of [PNGTuber Plus](https://kaiakairos.itch.io/pngtuber-plus)
by kaiakairos and adds a number of features around output, lighting, and
editing ergonomics while keeping the original's per-sprite physics and
parenting workflow.

## Contents

- [What it is](#what-it-is)
- [How it compares to PNGTuber Plus](#how-it-compares-to-pngtuber-plus)
- [Who it's for](#who-its-for)
- [GUI design](#gui-design)
- [Getting started](#getting-started)
  - [1. Download and launch](#1-download-and-launch)
  - [2. Loading an avatar](#2-loading-an-avatar)
  - [3. Editing](#3-editing)
  - [4. NDI into OBS](#4-ndi-into-obs)
- [Features in detail](#features-in-detail)
  - [Animation and physics](#animation-and-physics)
  - [Layer system](#layer-system)
  - [Eye tracking](#eye-tracking)
  - [Costume system](#costume-system)
  - [Visibility toggles](#visibility-toggles)
  - [Lighting (normal maps)](#lighting-normal-maps)
  - [NDI output](#ndi-output)
  - [Recording](#recording)
  - [Screenshot](#screenshot)
  - [Persistence](#persistence)
  - [Editor ergonomics](#editor-ergonomics)
  - [Microphone and voice activation](#microphone-and-voice-activation)
  - [Background and window](#background-and-window)
  - [Stream Deck integration](#stream-deck-integration)
- [Keyboard shortcuts](docs/keyboard_shortcuts.md)
- [Roadmap](#roadmap)
- [Tech notes](#tech-notes)
- [Credits](#credits)
- [Contributing](#contributing)
- [License](#license)

## What it is

You import PNGs (or a PSD), arrange them into a layered rig, set per-sprite
physics (wobble, drag, rotation, talk/blink frames), and the app renders the
avatar in real time. The avatar reacts to your microphone, and you can
either show it directly in a transparent window or broadcast it to OBS via
NDI.

## How it compares to PNGTuber Plus

PNGTuber Plus is the project this is built on. If you've used it, the
sprite-list, parenting model, sine-wave wobble, drag, bounce, and
talk/blink visibility rules will all be familiar. They work the same way
here.

What's added on top:

- **NDI output.** Broadcasts the avatar directly to OBS (or any NDI
  receiver) as a network video source with a transparent background. No
  chroma key or screen capture required.
- **Recording.** Record to WebM (VP9 alpha), animated PNG, or animated GIF
  with transparent backgrounds. Configurable frame rate.
- **Screenshot with transparent background.** `Ctrl+K` saves the current
  frame as a transparent PNG.
- **Eye tracking.** Per-sprite eye tracking with two modes: follow the
  cursor, or follow another sprite in the rig. Includes invert, tracking
  distance, and tracking speed.
- **Normal maps.** Pair a `_NRML`-suffixed image with any diffuse sprite
  for lighting response (UI for placing lights is on the roadmap, see
  below).
- **PSD import.** Drop a `.psd` and each Photoshop layer becomes a sprite,
  preserving group hierarchy and layer order.
- **Undo/redo.** Most edit operations are reversible.
- **Rotational limits.** Clamp how far each sprite can rotate (min and
  max angle).
- **Static elements.** Mark a sprite to ignore the avatar-wide bounce
  while still receiving its own wobble, drag, and rotation.
- **Clip linked sprites.** Render a child sprite only inside its
  parent's bounds.
- **NDI reference layer.** Designate one sprite as the framing anchor
  so the NDI broadcast doesn't drift when other sprites move.
- **Squash/stretch.** Vertical-velocity-driven scaling for a more
  exaggerated bounce feel.
- **Resizable, persistent sidebars.** Drag the inner edge of either
  sidebar to resize. Widths are saved between sessions.
- **Auto-restore last avatar.** The most recently saved or loaded
  avatar is reopened on startup.
- **Native file pickers.** Save and Load use the OS file picker (Finder
  on macOS, Explorer on Windows) instead of Godot's themed dialog.

Things both apps have (so they aren't in the list above): per-sprite
animation frames, parent-child relationships, drag, bounce, sine-wave
wobble, talk/blink visibility, costume hotkeys, hotkey-toggled sprite
visibility, custom background color, StreamDeck integration.

## Who it's for

- Streamers who already use PNGTuber Plus and want NDI output, recording,
  or eye tracking.
- VTubers who'd rather drop a layered PSD in than wire up sprites one by
  one.
- Content creators who want to grab a transparent screenshot or short
  clip of the avatar for thumbnails or social posts.
- Anyone setting up an OBS pipeline who'd rather avoid chroma key and
  screen capture.

## GUI design

There are three persistent regions:

1. **Top menu bar.** Exit, Import, Duplicate, Replace, Save, Load, Clear,
   Reset.
2. **Left sidebar (edit mode only).** Per-sprite controls for the
   currently selected sprite, in order from top to bottom:
   - Preview thumbnail
   - Normal-map import/clear
   - Position, offset, parent, layer info (read-only)
   - Animation frames + speed
   - Drag
   - Squash + rotational drag
   - Toggles: ignore bounce, clip linked sprites, static element, NDI
     reference layer
   - X frequency/amplitude, Y frequency/amplitude (wobble)
   - Rotational limits min/max + a live rotation gauge
3. **Right sidebar (always visible).** Avatar-wide controls:
   - Top row: speaking/blinking preview, link, unlink, trash
   - Layer search/filter
   - Sprite list
   - A draggable divider sets where the sprite list ends and the
     controls below begin
   - Costume buttons (10 quick-switch icons)
   - Eye tracking: enable, invert, mode (Cursor/Layer), pick target,
     distance, speed
   - Visibility toggle: bind a key to show/hide the selected sprite

The bottom-right corner holds the non-edit-mode controls: microphone,
settings, edit-mode toggle, volume/sensitivity meters, zoom indicator,
version.

The whole UI lives on a CanvasLayer, so it stays put when you pan or zoom
the canvas. Spacing follows two shared constants (a per-row gap and a
divider padding) so adjusting one value reflows the whole panel.

## Getting started

### 1. Download and launch

Grab the latest release for your platform from the Releases page.

- **macOS**: a `.dmg` containing `PixelLab Studio.app`. Drag it to
  Applications. On first run, macOS may show a Gatekeeper warning;
  right-click the app and choose Open.
- **Windows**: a `.zip` containing the executable. Extract it anywhere
  and run.

On first launch you'll see an empty canvas. Use Import or Load from the
top menu to bring a character in.

### 2. Loading an avatar

Three ways to start:

- **Import a PSD.** Pick a `.psd` from Import. Each Photoshop layer
  becomes a sprite, groups become parent relationships, and the rig is
  positioned around the world origin. Layers ending in `_NRML`
  (case-insensitive) auto-pair as normal maps for their matching diffuse
  layer.
- **Import PNGs.** Import accepts one or more `.png` files. Once they're
  in the scene you can set frame count (for sprite sheets), parents, and
  per-sprite properties.
- **Load a saved rig.** Load opens a `.save` file from any previous
  session. The most recently saved or loaded avatar reopens
  automatically the next time you launch the app.

Save with Save in the top menu. A progress bar appears while images
encode, then a confirmation toast appears on completion. Saves default
to the user data directory; the native file picker lets you navigate
anywhere from there.

### 3. Editing

Click any sprite on the canvas to select it; its controls appear in the
left sidebar. Right-click any slider to reset that property to its
default.

To set a sprite's pivot point (the white dot), use origin mode and drag
the dot to the desired pivot. To parent one sprite to another, use the
Link button at the top of the right sidebar and connect the child to its
parent. Eye-tracking layer mode uses a similar pick-and-connect flow from
the Pick button next to the eye-tracking mode dropdown.

For a full list of keyboard shortcuts (editing, camera, undo/redo,
recording, costumes, mouse interactions, and the Mac-specific notes on
modifier keys), see [docs/keyboard_shortcuts.md](docs/keyboard_shortcuts.md).

### 4. NDI into OBS

1. Open the settings menu (gear icon, bottom-right) and turn on **NDI
   Output**.
2. Optionally set the NDI source name (this is what OBS will see).
3. In OBS, install the obs-ndi plugin
   ([DistroAV](https://github.com/DistroAV/DistroAV)) if you don't have
   it.
4. Add Source → NDI Source, pick `PixelLab Studio` (or your custom name)
   from the dropdown.

The avatar shows up in OBS with a transparent background. A dashed
orange line on the canvas marks the bottom crop boundary for the NDI
frame. Drag it up to crop tighter for a head-and-shoulders shot. The
NDI output dynamically reframes based on the rig.

## Features in detail

### Animation and physics

- **Talk and blink frames.** Each sprite's `showOnTalk` and `showOnBlink`
  settings determine which frame plays for each state. Frame 0 is the
  rest pose; later frames cycle based on the sprite's animation speed.
- **Sprite-sheet animation.** Set frames > 1 and a speed and the sprite
  cycles through its sheet (mouths, breathing, idle accessories).
- **Wobble.** Independent X and Y sine-wave oscillation, each with its
  own frequency and amplitude.
- **Drag.** A lerped follow-with-lag offset, so large sprites trail
  behind smaller ones during a bounce.
- **Squash and stretch.** Driven by vertical velocity; the sprite
  stretches as it falls and squashes on contact, by a tunable amount.
- **Rotational drag.** Sprites tilt slightly in the direction of vertical
  motion as the avatar bounces.
- **Rotational limits.** Independent min and max angle clamps, with a
  live rotation gauge shown in the editor.

### Layer system

- **Parenting.** Any sprite can be parented to another; children inherit
  position, rotation, and bounce from their parent.
- **Filter.** The filter field above the sprite list narrows the visible
  list as you type.
- **Static element.** Ignore avatar-wide bounce while still receiving
  wobble, drag, and rotation. Useful for backdrops or stable accessories.
- **Clip linked.** Render a sprite only inside its parent's visual
  bounds.
- **NDI reference layer.** Mark one sprite so the NDI output framing
  anchors to it instead of drifting.

### Eye tracking

- **Cursor mode.** Eyes follow the mouse cursor.
- **Layer mode.** Eyes follow another sprite. Pick the target with the
  Pick button (drag the line to the target sprite on the canvas or in
  the sprite list).
- **Per-sprite enable.** Each "eye" sprite has its own toggle.
- **Global kill switch.** When no sprite is selected, the eye-tracking
  toggle controls all eye-tracking-enabled sprites at once.
- **Invert direction.** Look away from the target instead of at it.
- **Distance and speed.** Independent per sprite.

### Costume system

- 10 costume slots, switchable via hotkeys `1` through `0` (configurable
  in settings, removable individually since v1.4.5).
- Each sprite specifies which slots it appears in.
- Optional "bounce on costume change" setting.

### Visibility toggles

Bind any key to show/hide a specific sprite. Useful for ad-hoc props
(a sign that pops up when you read chat, a celebration prop on bits).
Bindings are stored per sprite in the avatar save file. Also visible in
the sprite list as an inline toggle since v1.4.5.

### Lighting (normal maps)

Normal maps are a property of a diffuse sprite, not separate sprites.
You can either:
- Drop a `_NRML`-suffixed image next to its diffuse pair on import
  (case-insensitive auto-pair), or
- Use the Normal button in the left sidebar to attach one to the
  selected sprite manually.

The two textures are paired via `CanvasTexture` so they render together
with lighting response. UI for placing and animating lights is on the
roadmap.

### NDI output

- Dynamic framing based on the rig's silhouette plus a user-placed
  bottom crop line.
- Auto width or manual width/height.
- Custom source name (what shows up in OBS's NDI Source dropdown).
- Renders on its own SubViewport, so the editor UI doesn't appear in
  the broadcast.
- Available on macOS (universal), Windows (x64), and Linux (x64 and
  ARM64) via the `godot-ndi` plugin.

### Recording

- **WebM** (VP9 with alpha): full-quality transparent video.
- **APNG**: animated PNG with full alpha.
- **GIF**: animated GIF with one-bit alpha (palette-quantized).
- Configurable frame rate per recording.
- Records the NDI crop view when NDI is enabled; otherwise records the
  full canvas.

### Screenshot

`Ctrl+K` captures the current frame to a `.png` of your choice. Like
the recorder, respects NDI cropping when NDI is enabled.

### Persistence

- All settings (volume, microphone, NDI options, sidebar widths,
  background color, blink chance, recording format, etc.) are saved to
  the user data directory and restored on next launch.
- The most recently opened or saved avatar reopens at startup. If the
  file is missing or fails to parse, the app starts on an empty canvas.
- Save and Load use native OS file pickers, defaulting to the user data
  directory.

### Editor ergonomics

- Right-click any slider to reset that property to its default.
- Drag the right edge of the left sidebar (or the left edge of the
  right sidebar) to resize. Widths persist across sessions.
- Drag the divider between the sprite list and the costume row to
  resize either area.
- Wheel-scroll the left sidebar to reach long sections when the window
  is short.
- During a window-resize gesture, sprite physics are frozen so nothing
  stretches or jitters as the viewport changes.
- The UI lives on a CanvasLayer, so panning and zooming the canvas
  doesn't affect the editor layout.

### Microphone and voice activation

- Per-device microphone selection.
- Volume and sensitivity sliders with real-time meters.
- Right-click the mic icon to mute the input.
- Release-duration setting controls how long the avatar stays in the
  talking pose after voice drops below threshold.

### Background and window

- Custom background color (supports transparent for stream overlays not
  using NDI).
- Transparent-window option for compositing directly on a desktop.
- Configurable max FPS (default 60).
- Last window size is remembered.

### Stream Deck integration

The Elgato Stream Deck addon is bundled (originally from PNGTuber Plus).
Settings appear in the settings menu.

## Roadmap

Planned but not shipped yet:

- **Light2D UI controls.** Currently the renderer reads paired normal
  maps; the next step is a UI for placing, coloring, and animating
  lights.
- **Right-sidebar tabs.** Eye Tracking / Lighting / Details tabs to
  consolidate the bottom-half controls (and move the normal-map row
  and per-sprite toggles over from the left sidebar).
- **Settings dialog cleanup.** Apply the same spacing model the
  sidebars use.
- **Theme consolidation.** Move the inline slider/checkbox styling to
  a project-level theme so it can be tuned in one place.

## Tech notes

- Built with **Godot 4.6** (GL Compatibility renderer).
- Native GDExtensions: `godot-ndi` (NDI output), `psd-native` (PSD
  parsing), `godot-streamdeck-addon` (Stream Deck input).
- All UI on a single CanvasLayer (`UILayer`) for camera-independent
  rendering.

## Credits

PixelLab Studio is built on top of
[PNGTuber Plus](https://kaiakairos.itch.io/pngtuber-plus) by
[kaiakairos](https://kaiakairos.itch.io/). The core sprite-rig model,
parenting, wobble, drag, bounce, and talk/blink visibility behavior come
from that project. Additions in PixelLab Studio (NDI, recording, eye
tracking, normal maps, PSD import, undo/redo, rotational limits, the
various toggles and editor ergonomics) are the work of this fork's
contributors.

Some hardening and feature ideas were adapted from
[Entrak/PNGTuber-Plus](https://github.com/Entrak/PNGTuber-Plus), another
fork of the original project. The session auto-save / crash-recovery
flow in particular (`user://session.pngtp` plus a startup restore prompt)
was inspired by their `_auto_save_session` implementation.

## Contributing

Issues and pull requests are welcome. If you're working on UI,
`docs/architecture_guide.md` describes the spacing model, the layout
pass, and the persistence patterns used elsewhere in the codebase.

## License

See `LICENSE`.

Sources used to verify the PNGTuber Plus baseline:
- [PNGTuber Plus on itch.io](https://kaiakairos.itch.io/pngtuber-plus)
- [v1.4.5 devlog](https://kaiakairos.itch.io/pngtuber-plus/devlog/704463/v-145)
