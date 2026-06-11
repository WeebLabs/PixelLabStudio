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
- [Getting started (for avatar owners)](#getting-started-for-avatar-owners)
  - [1. Download and launch](#1-download-and-launch)
  - [2. Load your avatar](#2-load-your-avatar)
  - [3. Set up your microphone](#3-set-up-your-microphone)
  - [4. Get to know your avatar](#4-get-to-know-your-avatar)
  - [5. Go live with OBS (streaming and Discord)](#5-go-live-with-obs-streaming-and-discord)
- [For creators (building your own rig)](#for-creators-building-your-own-rig)
  - [Importing a PSD or PNGs](#importing-a-psd-or-pngs)
  - [Rigging and editing](#rigging-and-editing)
  - [Saving your work](#saving-your-work)
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

## Getting started (for avatar owners)

> **This section is for people who bought a ready-made avatar** and just
> want to get it on screen and into a stream or a Discord call. You don't
> need any art or software experience — if you've got the `.save` file
> that came with your purchase, you're a few minutes away from your
> character talking along with you.
>
> If instead you want to *build* an avatar from scratch — importing
> Photoshop files, arranging sprites, setting up the physics — head to
> [For creators](#for-creators-building-your-own-rig) below.

### 1. Download and launch

Grab the latest release for your platform from the
[Releases page](https://github.com/WeebLabs/PixelLabStudio/releases).

- **macOS**: you'll get a `.dmg` file. Open it and drag **PixelLab
  Studio** into your Applications folder. The first time you open it,
  macOS may warn that it's from an unidentified developer — that's
  normal for indie apps. Right-click (or Control-click) the app icon and
  choose **Open**, then confirm. You only have to do this once.
- **Windows**: you'll get a `.zip` file. Right-click it, choose **Extract
  All**, then open the folder and double-click `PixelLab Studio.exe`. You
  can move that folder anywhere you like (for example, your Desktop).

When the app opens you'll see an empty stage with a small cluster of
controls in the **bottom-right corner**. The app starts in *display
mode*, which keeps the screen clean for streaming — so the menu you need
for loading isn't showing yet. The next step walks you through revealing
it.

### 2. Load your avatar

Your purchase downloads as a **`.zip` file**. Inside it is a **`.save`
file** — that single file *is* your avatar (artwork, layers, and movement
all bundled together). Before you can load it, you need to **unzip
(extract)** the download so the app can see the `.save` file inside.
Follow these steps in order:

1. Find the **`.zip` file** you downloaded (usually in your **Downloads**
   folder) and extract it:
   - **Windows**: right-click the `.zip`, choose **Extract All…**, then
     click **Extract**. A new folder opens with the contents inside.
   - **macOS**: double-click the `.zip`. A new folder with the same name
     appears right next to it.
   You should now see a **`.save` file** in the extracted folder — that's
   your avatar. (Loading straight from inside the `.zip` won't work, which
   is why this step matters.)
2. Now open the app's loading menu. In the **bottom-right corner** of the
   window, find the **pencil icon** (it sits near the microphone and gear
   icons) and click it. This switches the app from display mode into
   **Edit mode**.
3. A **menu bar now appears across the top** of the window, with buttons
   like Exit, Import, Save, and **Load**.
4. Click **Load** in that top menu bar.
5. A file window opens (Finder on macOS, File Explorer on Windows).
   Navigate to the **extracted folder** from step 1, click the **`.save`
   file**, and choose **Open**.
6. Your character appears on the stage. 🎉
7. When you're happy, click **Exit** at the far-left of the top menu bar
   to leave Edit mode and return to the clean display view. (You can
   always click the pencil icon again later if you need the menu back.)

That's it — you don't need to set anything else up. The next time you
launch the app, your avatar **reopens automatically**, so you only have
to load it this once.

### 3. Set up your microphone

This is what makes the magic happen: the app listens to your mic and your
avatar's mouth moves when you talk.

1. Click the **gear icon** in the bottom-right corner to open settings.
2. Find the **microphone** option and pick the same mic you use for
   streaming or calls (a headset, USB mic, etc.).
3. Speak normally and watch the meters next to the mic icon move. If your
   avatar isn't reacting, nudge the **sensitivity** up; if it looks like
   it's talking constantly, nudge it down.

To **mute** quickly, right-click the mic icon in the bottom-right corner.

### 4. Get to know your avatar

A few things worth knowing so you feel at home:

- **Costumes / outfits.** If your avatar came with extra looks, press the
  number keys **`1`–`0`** to switch between them on the fly.
- **Move the camera.** Scroll to zoom in or out, and hold the middle
  mouse button (or spacebar) to drag the view around. This only changes
  what *you* see — it doesn't affect your stream.
- **Edit mode.** The **pencil icon** in the bottom-right corner switches
  Edit mode on and off (the same one you used to load your avatar). With
  it on, you can click your avatar and **drag it to reposition** it, or
  use the on-screen handles to **resize** it so it sits where you want on
  screen. Click **Exit** in the top menu bar (or the pencil again) when
  you're done, so you don't move things by accident.
- **Reset a setting.** If you ever change a slider and want it back to how
  it was, right-click that slider.

That's all most people ever need. If you get curious later, the
[Features in detail](#features-in-detail) section and the
[keyboard shortcuts list](docs/keyboard_shortcuts.md) cover everything
else.

### 5. Go live with OBS (streaming and Discord)

PixelLab Studio sends your avatar to OBS as a clean, **transparent video
source** — no green screen and no screen-grabbing a window. Here's the
one-time setup.

**In PixelLab Studio:**

1. Open settings (the **gear icon**, bottom-right) and turn on **NDI
   Output**. (NDI is just the technology that carries the video to OBS —
   you don't need to understand it, only switch it on.)
2. Leave the source name as is, or give it a name you'll recognize in the
   next step.

**In OBS (one-time install):**

3. If you've never used NDI with OBS, install the free **DistroAV**
   plugin from
   [distroav.org](https://github.com/DistroAV/DistroAV), then restart
   OBS.

**In OBS (add your avatar):**

4. Under **Sources**, click **+** → **NDI Source**.
5. In the dropdown, choose **PixelLab Studio** (or the name you set), then
   click **OK**.

Your avatar now appears in OBS with a see-through background, ready to
layer over your game, camera, or scene. Back in PixelLab Studio you'll
see a dashed **orange line** across the stage — that's the bottom edge of
what OBS receives. Drag it up if you only want a head-and-shoulders view.
The framing follows your avatar automatically as it moves.

**Using your avatar on Discord (or Zoom, Meet, etc.):**

Discord can't read NDI directly, but OBS bridges the gap with a built-in
**Virtual Camera**:

6. In OBS, click **Start Virtual Camera** (right-hand controls).
7. In Discord, open **User Settings → Voice & Video** (or your video
   options on a call) and choose **OBS Virtual Camera** as your camera.

Your avatar now shows up anywhere that picks a webcam. The same OBS setup
covers both your stream and your calls, so you only build it once.

## For creators (building your own rig)

The steps above assume someone already assembled your avatar for you. If
you're making one yourself — or tweaking the rigging of one you bought —
this is where you bring in artwork and wire up how the pieces move. This
part expects some comfort with layered image files (Photoshop/PSD) and a
bit of patience for fiddling with settings.

### Importing a PSD or PNGs

Two ways to bring artwork in, both from **Import** in the top menu bar:

- **Import a PSD.** Pick a `.psd` and each Photoshop layer becomes its
  own sprite, Photoshop groups become parent/child relationships, and the
  whole rig is positioned around the world origin. Layers whose names end
  in `_NRML` (case-insensitive) automatically pair up as normal maps for
  their matching artwork layer — handy for lighting later.
- **Import PNGs.** Import also accepts one or more `.png` files. Once
  they're on the stage you can set a frame count (for sprite-sheet
  animations like talking mouths), choose parents, and tune each sprite's
  properties individually.

### Rigging and editing

Click any sprite on the stage to select it; its controls appear in the
left sidebar. Right-click any slider to reset that property to its
default.

- **Pivot points.** To set where a sprite rotates from (the white dot),
  enter origin mode and drag the dot to the spot you want.
- **Parenting.** To attach one sprite to another so it follows along, use
  the **Link** button at the top of the right sidebar and connect the
  child to its parent.
- **Eye tracking.** Layer mode uses the same pick-and-connect flow: hit
  the **Pick** button next to the eye-tracking mode dropdown and draw a
  line to the sprite the eyes should follow.

For the full set of keyboard shortcuts (editing, camera, undo/redo,
recording, costumes, mouse interactions, and the Mac-specific notes on
modifier keys), see
[docs/keyboard_shortcuts.md](docs/keyboard_shortcuts.md).

### Saving your work

Click **Save** in the top menu. A progress bar appears while the images
encode, followed by a confirmation message when it's done. Saves default
to the app's data folder, but the file window lets you navigate anywhere
— and the resulting `.save` file is exactly the kind of self-contained
avatar file an end user loads in step 2 above.

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
