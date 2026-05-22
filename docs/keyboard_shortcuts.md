# Keyboard shortcuts

All shortcuts work the same on macOS and Windows unless noted. One thing to
know up front:

> **PixelLab Studio uses the physical `Control` key as its modifier on
> every platform, including macOS.** Where this guide says "Ctrl+something",
> macOS users press the `Control` key (often labelled `^`), not `Cmd`. Ctrl
> is the bottom-leftmost modifier on a standard Apple keyboard.

Shortcuts marked **configurable** can be remapped from the settings menu.
The rest are fixed in the project's input map and require a code change to
remap.

## Conventions

| Symbol | Meaning |
|---|---|
| `Key` | Press the named key once. |
| `Hold Key` | Press and hold the key while doing something else. |
| `A+B` | Press `B` while `A` is held. |
| `LMB` / `MMB` / `RMB` | Left / middle / right mouse button. |
| `Wheel` | Mouse scroll wheel. |

The app's behavior depends on a couple of states. Where a shortcut only
applies in one of them, it's called out:

- **Edit mode** vs **non-edit mode**: toggled with the pencil button in
  the bottom-right of the canvas. Most editing shortcuts only fire in
  edit mode.
- **A sprite is selected**: most per-sprite shortcuts only fire when
  there's a held sprite (click one on the canvas to select).
- **Cursor is not in a text field**: typing in the layer-list filter,
  the z-index input, or any other text box suppresses single-letter
  shortcuts so you can type normally.

## Mode switching and global state

| Shortcut | What it does |
|---|---|
| `P` | Toggle reparent (link) mode. Canvas background turns blue. Click a parent sprite to attach the held sprite to it; click again or press `P` to cancel. Right-click also cancels. |
| `Hold O` | Enter origin-adjustment mode. Canvas background turns purple. Drag the white dot on the selected sprite to set its pivot. Release to exit. |
| `Tap O` | Snap the selected sprite's origin to the current cursor position. |
| `Esc` | Open the project's user data folder in the OS file browser (when no text field is focused). Also cancels the z-index input overlay. |
| `R` | Refresh / re-evaluate the avatar (rebuilds visibility, parenting cache, etc.). |

## Per-sprite editing

You must have a sprite selected (clicked on the canvas) for these:

| Shortcut | What it does |
|---|---|
| `W` / `A` / `S` / `D` | Nudge the selected sprite up / left / down / right. While `O` is held, nudges the sprite's origin instead. Hold the key for continuous movement; undo state is captured at the start of each held burst. |
| `Q` / `E` | Decrease / increase the sprite's z-index by 1. |
| `N` | Open the z-index input overlay so you can type a specific layer number. Press `Esc` or click outside the input to cancel. |
| `U` | Unlink the selected sprite from its parent. |
| `RMB` on slider | Reset that slider to its property's default value. |
| `RMB` on layer mode dropdown | While in eye-tracking layer mode, clear the assigned target. Cursor mode is a no-op. |

## Camera

| Shortcut | What it does |
|---|---|
| `Hold MMB` + drag | Pan the canvas camera. |
| `Ctrl+Wheel up` / `Ctrl+Wheel down` | Zoom in / zoom out. Range is roughly 10% to 400%. |
| `Ctrl+↑` / `Ctrl+↓` | Same as `Ctrl+Wheel` (zoom in / out) on systems without a wheel. |
| `Wheel up` / `Wheel down` (over canvas) | Cycle through sprites in z-index order, selecting the next one. Suppressed when the cursor is over the left sidebar. |

## Undo, redo, save

| Shortcut | What it does |
|---|---|
| `Ctrl+Z` | Undo the last edit operation. |
| `Ctrl+Y` | Redo. |
| `Ctrl+L` | Save each sprite's image data out as individual PNG files alongside the avatar. Useful for extracting sprites from a project. |
| `Ctrl+K` (tap) | Take a screenshot of the current frame with a transparent background. Opens a save dialog. If NDI is enabled, captures the NDI crop view instead of the full canvas. |
| `Ctrl+K` (hold ≥1 second) | Start recording. Release to stop and save (format: WebM, GIF, or APNG, per the setting). |

## Voice activation

| Shortcut | What it does |
|---|---|
| `Hold M` | Simulate microphone input (force the avatar into talking pose). Useful for testing rigs without speaking. |
| `RMB` on the mic icon (bottom-right) | Toggle mute on the microphone input. |

## Sidebar interaction

| Shortcut | What it does |
|---|---|
| Drag inner edge of either sidebar | Resize the sidebar. Width persists across sessions. |
| Drag the divider between the layer list and the costume row | Resize the layer-list area. |
| `Wheel` over the left sidebar | Scroll the panel up/down when the window is too short to show the whole thing. |

## Costume hotkeys (configurable)

By default, keys `1` through `0` (across the top of the keyboard) switch
between the 10 costume slots. Each slot can be re-bound from
**Settings → Costume hotkeys**, and individual costume hotkeys can be
disabled if you want to free up a key.

| Default key | Costume |
|---|---|
| `1` | Costume 1 |
| `2` | Costume 2 |
| `3` | Costume 3 |
| `4` | Costume 4 |
| `5` | Costume 5 |
| `6` | Costume 6 |
| `7` | Costume 7 |
| `8` | Costume 8 |
| `9` | Costume 9 |
| `0` | Costume 10 |

## Visibility toggles (configurable, per sprite)

Each sprite can have one key bound to show/hide it. Set the binding from
the Visibility Toggle row in the right sidebar (with the sprite
selected): click **Set Key**, then press the key you want. The binding
is stored in the avatar's `.save` file.

There is no default for these, since every avatar uses different props.

## Mouse summary

| Action | What it does |
|---|---|
| `LMB` on a sprite | Select that sprite (becomes the held sprite). |
| `LMB` on canvas (empty) | Deselect any held sprite. |
| `LMB` on a sprite in the layer list | Select that sprite. |
| `Drag LMB` from the Pick button (eye tracking) | Whip-pick a target sprite for layer-mode eye tracking. |
| `Drag LMB` from the Link button (top of right sidebar) | Reparent the held sprite to whichever sprite you drop the line on. |
| `MMB` drag on canvas | Pan camera. |
| `RMB` on canvas while reparenting | Cancel reparent mode. |
| `RMB` on canvas while eye-track picking | Cancel pick. |
| `RMB` on slider | Reset slider to its default. |
| `RMB` on mic icon | Toggle mic mute. |
| `RMB` on layer-mode dropdown | Clear the assigned layer target. |
| `Drag LMB` on the orange dashed line (NDI mode) | Move the NDI bottom crop boundary up or down. |
| `Drag LMB` on the right sidebar's internal divider | Resize the layer list area. |

## Note on Mac modifier conventions

Most Mac apps use `Cmd` as the primary modifier (`Cmd+Z` for undo,
`Cmd+S` for save, etc.). PixelLab Studio currently uses the physical
`Control` key as its modifier on every platform, including macOS, so
you'd press `Control+Z` to undo. This is unconventional on Mac and is
something the project may revisit; for now, train your muscle memory on
`Control` rather than `Cmd` when using PixelLab Studio on Mac.

The OS-level shortcuts (`Cmd+Q` to quit, `Cmd+W` to close, `Cmd+H` to
hide, `Cmd+Tab` to switch app) still work as you'd expect, since those
are handled by the OS rather than the app.

## Customizing shortcuts in the project

Most shortcuts are defined in `project.godot` under the `[input]`
section. Each entry binds an action name (e.g., `undo`, `screenshot`,
`reparent`) to one or more `InputEventKey` or `InputEventMouseButton`
entries. To remap globally, edit the relevant entry's `physical_keycode`
in `project.godot` and rebuild the app.

Costume keys and per-sprite visibility toggles aren't in the input map;
they're stored in `Saving.settings["costumeKeys"]` and each sprite's
`toggle` property, respectively, and are user-editable at runtime via
the settings menu and the right sidebar.
