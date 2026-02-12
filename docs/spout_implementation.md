# Spout Output Implementation

## Overview

Add a Spout2 video output to PNGTuberPlus so that the avatar can be shared directly to OBS and other applications as a live texture with transparency, eliminating the need for green screen or window capture.

---

## Architecture

### SubViewport approach

- Add a **SubViewport** node with its own **Camera2D** that renders the avatar independently of the main viewport
- The SubViewport has `transparent_bg = true`, providing alpha-keyed output natively
- A Spout2 GDExtension plugin sends the SubViewport's texture to receiving applications
- On macOS, the equivalent would be a Syphon plugin

### Spout plugin

- Community GDExtension plugins exist for Spout2 in Godot 4
- The plugin takes a `ViewportTexture` from the SubViewport and shares it via Spout's shared texture mechanism
- Spout is Windows-only; Syphon is the macOS equivalent
- The Spout sender should be named something identifiable (e.g., "PNGTuberPlus") so it's easy to find in OBS

---

## Camera Framing

### The problem

- The avatar bounces upward during costume changes and speech events (OriginMotion.position.y goes negative, returns to 0)
- At rest, the avatar is at its lowest position
- During bounce, it rises by an amount determined by initial velocity and gravity
- The Spout output needs to frame the avatar so:
  - The bottom of the avatar is never visible during bounce (no gap below)
  - The top of the avatar is never clipped at rest or during bounce
  - The frame is tight enough that the avatar doesn't look tiny

### The ruler approach

The user positions a draggable horizontal line in the viewport (edit mode) to mark the bottom boundary of their model. This is better than a "select a reference layer" approach because:

- It's visually obvious and intuitive
- It works regardless of model complexity
- The user can account for hair, dangling accessories, etc. (things that shouldn't define the bottom)
- It's trivial to persist (just a Y coordinate)
- The user can see wobble/stretch in action and position the line to account for it

The ruler position (`crop_y`) is saved in the avatar data and/or settings.

### Viewport sizing

The SubViewport dimensions are **computed from the content**, not the other way around:

1. User sets a **width** (or picks a preset: 512, 1080, etc.)
2. User positions the **ruler** for the bottom crop
3. System computes **height** from:
   - Top: highest sprite top edge - bounce headroom
   - Bottom: ruler position (`crop_y`)
   - Bounce headroom = `yVel_initial^2 / (2 * bounceGravity)` (peak displacement from kinematics)
4. SubViewport is sized to exactly fit the content at native resolution
5. Camera is positioned so `crop_y` aligns with the viewport bottom edge

The Spout camera does **not** follow the bounce. It stays fixed. The avatar moves within it:

- At rest: avatar fills the lower portion of the frame, empty space above (bounce headroom)
- At peak bounce: avatar rises to fill the upper portion
- Bottom is never visible because the camera is anchored to `crop_y`

### Why not fixed resolution + zoom?

Using a fixed-resolution viewport and adjusting camera zoom to accommodate changing bounce settings was considered and rejected:

- When bounce is small, the avatar fills the frame nicely
- When bounce is large, the camera zooms out, making the avatar smaller and wasting resolution on empty space
- The user would need to set an unnecessarily high viewport resolution to compensate
- This is an awkward tradeoff with no benefit

### Why not dynamic zoom at all?

The viewport only needs to resize when **settings change** (bounce amplitude, gravity, ruler position), not during normal operation. Users adjust these during setup, not mid-stream. So:

- During setup: viewport recalculates and resizes when settings change; OBS picks up the new size automatically (Spout2 receivers handle resolution changes)
- During streaming: viewport is fixed, avatar bounces within the pre-calculated space, output is stable

This gives pixel-perfect framing at all times without wasted resolution.

### Optional manual resolution override

Offer two modes:

- **Auto mode**: system computes optimal viewport dimensions from content + bounce headroom
- **Manual mode**: user sets an exact output resolution (e.g., 800x1200); system computes camera zoom to fit content into that resolution. Trades some resolution efficiency for a fixed, predictable output size. Useful when a receiving application expects a specific resolution.

---

## Bounce Headroom Calculation

Current bounce code in `main.gd _process()`:

```gdscript
origin.get_parent().position.y += yVel * 0.0166
if origin.get_parent().position.y > 0:
    origin.get_parent().position.y = 0
yVel += bounceGravity * 0.0166
```

Peak displacement (from basic kinematics): `peak = yVel_initial^2 / (2 * gravity)`

Note: The hardcoded `0.0166` instead of `delta` means the actual peak depends on framerate. If this is fixed to use `delta` (as recommended in the evaluation), the kinematics formula becomes exact. If not, the headroom calculation should add a small safety margin (~10-15%) to account for framerate variance.

The bounce headroom also needs to account for:

- **Wobble**: sprites with `yAmp` can extend above their rest position by `yAmp` pixels
- **Stretch**: sprites with `stretchAmount` can elongate vertically during bounce
- **Eye tracking offset**: sprites with eye tracking can shift by up to `eyeTrackDistance` pixels

A practical approach: compute the theoretical peak from kinematics, then add a configurable margin (default ~15%) that absorbs wobble/stretch/tracking without needing to calculate each individually.

---

## Avatar Bounding Box

To compute the top of the avatar for framing:

- Iterate all sprites in the `"saved"` group
- For each visible sprite (accounting for current costume layer), get its global bounds: `global_position + offset - (size * 0.5)` for the top edge
- The highest point across all sprites defines the avatar top
- This only needs recalculating when the avatar is loaded, sprites are moved, or settings change -- not every frame

---

## UI Controls

### Edit mode additions

- **Ruler line**: a draggable horizontal line in the viewport, visible only in edit mode. Styled distinctly (e.g., dashed line, different color from selection outlines). Drag handle at one or both ends.
- **Spout settings panel** (in settings menu or a dedicated section):
  - Toggle: enable/disable Spout output
  - Width input or preset selector (512, 720, 1080, custom)
  - Auto/manual mode toggle
  - Manual resolution inputs (when in manual mode)
  - Preview of the Spout output frame (optional, could be a small picture-in-picture)

### Display mode

- The ruler is hidden
- The Spout SubViewport renders continuously
- A small indicator (e.g., icon in control panel) shows Spout is active

---

## Implementation Order

1. Add SubViewport + Camera2D to the main scene, rendering the avatar with transparent background
2. Add the ruler (draggable Y-position line in edit mode), persist the value
3. Implement viewport sizing logic (content bounds + bounce headroom)
4. Integrate a Spout2 GDExtension plugin, wire it to the SubViewport texture
5. Add UI controls for enabling Spout, setting width, auto/manual mode
6. Wire bounce/gravity setting changes to trigger viewport recalculation
7. Save/load Spout settings (enabled, width, mode, ruler position)
8. Add to undo system if ruler position changes are undoable

---

## Open Questions

- Which Spout2 GDExtension to use? Need to evaluate available plugins for Godot 4 compatibility and maintenance status.
- Syphon support for macOS -- is there a comparable GDExtension, or is this Windows-only for now?
- Should the ruler position be per-avatar (saved in the .pngtp file) or global (saved in settings)?
  - Per-avatar makes more sense since different avatars have different proportions.
- Should the Spout output include UI elements like the push update notifications, or only the avatar?
  - Only the avatar. The SubViewport camera only sees the avatar layer.
- NDI as an alternative/addition to Spout? NDI has broader cross-platform support but higher latency.
