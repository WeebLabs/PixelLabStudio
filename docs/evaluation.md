# PNGTuberPlus Codebase Evaluation

Comprehensive code quality analysis covering all major subsystems: autoload scripts, sprite objects, main scene/UI, data persistence, PSD parsing, and project configuration.

---

## Table of Contents

1. [Critical Issues](#1-critical-issues)
2. [Major Issues](#2-major-issues)
3. [Minor Issues](#3-minor-issues)
4. [Performance Concerns](#4-performance-concerns)
5. [Security Concerns](#5-security-concerns)
6. [Architecture & Anti-Patterns](#6-architecture--anti-patterns)
7. [Summary Statistics](#7-summary-statistics)

---

## 1. Critical Issues

### C1. `str_to_var()` used on save file data (Remote Code Execution risk)
**File:** `main_scenes/main.gd` lines 87, 100, 491, 511, 540
**File:** `autoload/undo_manager.gd` lines 126, 127, 148, 194, 207, 222

`str_to_var()` in Godot can instantiate arbitrary objects and is equivalent to `eval()`. It is used to deserialize window size, background color, sprite offset, costume layers, and sprite position from save files. If a malicious or corrupted save file is loaded, this could execute arbitrary code. The safe alternative is to parse the expected types manually (e.g., parse a `Vector2` from its components).

### C2. Null dereference crash in `_process` when `main` is null
**File:** `autoload/global.gd` lines 163, 176

`main.editMode` and `!main.fileSystemOpen` are accessed unconditionally every frame, outside the `if main != null` guard at line 95. If `main` is null (during early frames before the main scene assigns `Global.main = self`), this crashes.

### C3. `write_save()` and `write_settings()` crash on null FileAccess
**File:** `autoload/saving.gd` lines 99-106

`FileAccess.open()` can return `null` if the path is invalid or permissions prevent writing. There is zero null checking. `write_settings` is called from `_exit_tree`, meaning this will crash on application shutdown if the settings file cannot be opened.

### C4. `deleteAllMics()` destroys ALL children of the Global node
**File:** `autoload/global.gd` lines 87-89

```gdscript
func deleteAllMics():
    for child in get_children():
        child.queue_free()
```

This removes every child node of the Global autoload, not just microphone AudioStreamPlayers.

### C5. Recursive async microphone loop with no cancellation
**File:** `autoload/global.gd` lines 71-85

`createMicrophone()` is an infinite recursive `await` chain. Each invocation creates a new coroutine that is never explicitly cancelled. Multiple overlapping coroutine chains can run simultaneously if `createMicrophone` is called externally.

### C6. Unguarded `spectrum` access in `_process`
**File:** `autoload/global.gd` line 101

`spectrum.get_magnitude_for_frequency_range(20, 20000).length()` runs every frame. If the audio bus configuration does not have bus index 1 with effect index 1, `get_bus_effect_instance` returns `null`, and line 101 crashes every frame.

### C7. Integer division in `drag()` breaks drag lag feature
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 393

```gdscript
dragger.global_position = lerp(dragger.global_position, wob.global_position, 1/dragSpeed)
```

`dragSpeed` is declared as `var dragSpeed = 0` (an integer). For any `dragSpeed > 1`, `1/dragSpeed` performs **integer division** evaluating to `0`, meaning `lerp(..., 0)` produces no movement. The drag lag feature is effectively non-functional.

### C8. Array out-of-bounds crash on parent lookup
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 168-173

```gdscript
var nodes = get_tree().get_nodes_in_group(str(parentId))
get_parent().remove_child(self)
nodes[0].sprite.add_child(self)  # CRASH if nodes is empty
```

No check that `nodes` is non-empty before accessing `nodes[0]`. The 0.1-second timer is a race condition with no guarantee the parent sprite exists by then.

### C9. Hardcoded frame-time constant instead of delta
**File:** `main_scenes/main.gd` lines 156, 161

```gdscript
origin.get_parent().position.y += yVel * 0.0166
yVel += bounceGravity * 0.0166
```

The `_process(delta)` function receives actual delta but uses `0.0166` (~1/60) instead. At 30 FPS, bounce physics run at half speed; at 144 FPS, at 2.4x speed.

### C10. Settings only persisted at clean exit -- crash loses all changes
**File:** `autoload/saving.gd` lines 71-72

Settings are only written in `_exit_tree()`. If the application crashes, is killed by the OS, or exits abnormally, all settings changes since the last launch are lost.

### C11. JavaScript injection in web builds
**File:** `autoload/saving.gd` lines 96-97, 126-136

URLs and data are directly concatenated into `JavaScriptBridge.eval()` strings without escaping. If data contains quotes, arbitrary JavaScript can execute.

### C12. Stream Deck config loading has no null check
**File:** `addons/godot-streamdeck-addon/singleton.gd` lines 83-84

If the config file does not exist, `file` is `null` and `file.get_as_text()` crashes.

---

## 2. Major Issues

### M1. Sprite ID collision risk (`randi()` without proper seeding)
**File:** `main_scenes/main.gd` lines 307-308, 321-322, 647-648

A new `RandomNumberGenerator` is instantiated without calling `randomize()` each time. `randi()` returns a 32-bit integer; with the birthday paradox, collisions become probable with many sprites across sessions. ID collisions corrupt the parent-child hierarchy.

### M2. `costumeLayers` padding logic adds wrong number of elements
**Files:** `main_scenes/main.gd` lines 512-514, `autoload/undo_manager.gd` lines 208-210

```gdscript
if sprite.costumeLayers.size() < 8:
    for i in range(5):
        sprite.costumeLayers.append(1)
```

Checks `< 8` but always appends exactly 5. If size is 7, result is 12 (expected: 10). Should pad to exactly 10.

### M3. Profane signal and group names
**Files:** `main_scenes/main.gd` line 63, line 388; `autoload/global.gd` lines 199, 289

Signal `fatfuckingballs` and group name `"penis"` are used as UI identifiers. These appear across 12+ scene and script files.

### M4. Race condition in `_on_set_toggle_pressed` with dual await
**File:** `ui_scenes/spriteEditMenu/sprite_viewer.gd` lines 383-391

Between two `await` calls, `Global.heldSprite` can become `null`, leading to a null reference crash. Multiple invocations create competing coroutines.

### M5. Missing null guards on `heldSprite` in slider callbacks
**File:** `ui_scenes/spriteEditMenu/sprite_viewer.gd` lines 130-156

All `_on_*_value_changed` functions access `Global.heldSprite` without null checking. Only `_on_drag_slider_value_changed` has a guard.

### M6. Hardcoded 1920x1080 overlay size
**Files:** `main_scenes/main.gd` lines 358-360, `ui_scenes/psdImport/psd_import_dialog.gd` lines 37-40

Modal overlays are hardcoded to 1920x1080. On larger displays, users can click around the edges and interact with sprites behind the modal.

### M7. Stale origin reference after `queue_free()`
**File:** `main_scenes/main.gd` lines 480-483, 839-842

`queue_free()` does not free the node until end of frame. During the remainder of the frame, both old and new origin nodes exist simultaneously.

### M8. Re-entrant `updateData()` race with await
**File:** `ui_scenes/spriteList/viewer.gd` lines 9-11

After clearing and before repopulating, there is a 0.15-second `await`. If `updateData()` is called again during this window, two coroutines race to populate the container, creating duplicate entries.

### M9. `_restore` can orphan nodes on failed reparent
**File:** `autoload/undo_manager.gd` lines 114-124

If the target parent is not found after `remove_child(self)`, the sprite is never re-added to any parent. This orphans the node (memory leak, invisible sprite).

### M10. `changeCollision()` duplicate line bug
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 427-429

```gdscript
func changeCollision(enable):
    grabArea.monitorable = enable
    grabArea.monitorable = enable  # should be grabArea.monitoring = enable
```

`monitoring` is never toggled. Hidden sprites can still detect area entries.

### M11. `remakePolygon()` uses Y for both collision dimensions
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 442

```gdscript
shape.size = Vector2(imageSize.y, imageSize.y)
```

Creates a square collision shape using only height for both dimensions. Non-square images have incorrect collision areas.

### M12. `replaceSprite()` does not reset `remadePolygon`
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 181

If `remadePolygon` was previously `true`, the new image's polygon remaking is silently skipped.

### M13. Toggle parameter shadows instance variable
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 459 vs line 94

`setClip(toggle)` parameter name shadows the instance variable `var toggle = "null"`.

### M14. `talkBlink()` truth table is opaque and potentially incomplete
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 285-289

The lookup table `[0,10,20,30,1,21,12,32,3,13,4,15,26,36,27,38]` maps 16 of 36 possible combinations. Whether missing entries are intentional or bugs cannot be determined from code.

### M15. Animation speed coupled to `Engine.max_fps`
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 272

`var speed = max(float(animSpeed), Engine.max_fps * 6.0)` -- changing FPS settings changes all animation speeds.

### M16. Fragile cross-object `_physics_process` enable/disable
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 332

When deselected, sprite disables its own `_physics_process`. Re-enabling depends on external code calling `set_physics_process(true)`.

### M17. Lerp factors not delta-adjusted (framerate-dependent physics)
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 393, 419, 425

`wobble()`, `rotationalDrag()`, `stretch()`, and `drag()` all use constant lerp factors in `_process()` without multiplying by delta. At 120fps they converge twice as fast as at 60fps.

### M18. Origin gizmo radius not zoom-compensated
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 265, 303

The 24-pixel hit radius is in world space. At low zoom levels, the gizmo becomes nearly impossible to click.

### M19. Hardcoded parent chain depth (`get_parent().get_parent().get_parent()`)
**File:** `autoload/global.gd` lines 211, 219

Assumes exactly 3 levels of parent hierarchy from Area2D to sprite root. If scene tree structure changes, this silently gets the wrong node.

### M20. `updateIndent()` can index out of bounds
**File:** `ui_scenes/spriteList/sprite_list_object.gd` lines 43-49

Loop walks backwards through siblings up to 64 positions without checking if `get_index()-1-i >= 0`.

### M21. No error feedback on save/load failure
**File:** `main_scenes/main.gd` lines 473-608

Load failure returns silently. Save has zero error handling. Push update fires unconditionally regardless of success.

### M22. PSD thread not joined on app exit
**File:** `main_scenes/main.gd` lines 336-428

No `_exit_tree()` handler to join the PSD parse thread. Failing to join a thread before exit can crash.

### M23. Double PSD import orphans thread
**File:** `main_scenes/main.gd` lines 341-351

Starting a new PSD import overwrites `_psd_thread` and `_psd_parser` without joining the previous thread.

### M24. Hardcoded notification constant `30`
**Files:** `main_scenes/main.gd` line 222, `main_scenes/EditControls.gd` line 78

Should use `NOTIFICATION_WM_SIZE_CHANGED` instead of raw integer.

### M25. PSD parser: no file position validation, no size limits
**File:** `autoload/psd_parser.gd` multiple locations

Parser does not validate file position against section bounds. No size limit on layer allocation -- a malformed PSD could exhaust memory.

### M26. PackBits decompression silently produces zeroed data on underflow
**File:** `autoload/psd_parser.gd` lines 63-94

If compressed data ends before expected, remaining bytes are zero (black pixels) rather than reporting an error.

### M27. Settings migration is inconsistent
**File:** `main_scenes/main.gd` lines 82-87

`volume`, `sense`, `windowSize`, `lastAvatar` keys have no `has()` guards, unlike other settings. Loading old settings files will crash.

### M28. No atomic write pattern -- data loss on crash during write
**File:** `autoload/saving.gd` lines 95-106

Files are opened with WRITE mode (which truncates), then written. A crash mid-write leaves corrupt/empty files.

### M29. Async error display races in `epicFail()`
**File:** `autoload/global.gd` lines 339-363

Multiple rapid `epicFail()` calls each create a timer. Earlier error messages disappear prematurely when later timers fire.

### M30. Wrong error variable passed in image load fallback
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 117

`Global.epicFail(err)` is called with `err` (file load error) instead of `errr` (buffer decode error).

### M31. `queue_free` + immediate `add_child` race in `replaceSprite()`
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 207-220

Old collision shapes are `queue_free()`'d but new ones are immediately added. Both coexist during the frame, causing potential double-hit detection.

### M32. Collision shapes not offset for animated sprites
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 440-445

`remakePolygon()` positions collision at `(imageSize.x, imageSize.y) * 0.5` but `imageSize` is the full spritesheet size. Collision does not align with the visible frame.

### M33. Duplicate sprite missing properties and shared array reference
**File:** `main_scenes/main.gd` lines 643-688

`stretchAmount`, `ignoreBounce`, `clipped`, `toggle` are not copied. `costumeLayers` is assigned by reference, not `.duplicate()`, so modifying one modifies the other.

### M34. No auto-save for avatar data
**File:** `main_scenes/main.gd` lines 551-608

Avatar data is only written when user explicitly saves. No periodic auto-save or save-on-exit for avatar data.

### M35. Undo stack holds 50 full base64 snapshots in memory
**File:** `autoload/undo_manager.gd` lines 1-56

Each snapshot includes base64-encoded PNG data for every sprite. For avatars with many large sprites, memory pressure can be significant.

### M36. `clearSave()` -- no null check on DirAccess, wrong extension
**File:** `autoload/saving.gd` lines 109-124

`DirAccess.open()` could return `null`. Also targets `.save` extension but avatar files use `.pngtp`.

### M37. PSD `status_text` String is not thread-safe
**Files:** `autoload/psd_parser.gd` line 27, `main_scenes/main.gd` lines 406-407

`String` in GDScript is not atomic. Reading `status_text` from the main thread while the parser thread writes it is a data race.

### M38. Volume/sensitivity sliders write to `Saving.settings` every frame
**Files:** `ui_scenes/volume/volumeSlider.gd` line 6, `ui_scenes/volume/sensitiveSlider.gd` line 6

Both sliders run `_process` every frame and unconditionally write `Saving.settings["volume"] = value` and `Saving.settings["sense"] = value`. They also compute `Global.volumeLimit = max_value - value` and `Global.senseLimit = max_value - value` every frame. These should be signal-driven via `value_changed` instead.

### M39. Stream Deck `return` instead of `continue` breaks packet processing
**File:** `addons/godot-streamdeck-addon/singleton.gd` line 45

```gdscript
if !(data.event == ButtonEvent.KEY_DOWN || data.event == ButtonEvent.KEY_UP):
    return
```

This `return` exits the entire `_process` function, not just the current packet iteration. If a non-key event arrives before key events in the queue, subsequent packets in the same frame are never processed. Should be `continue`.

### M40. Settings menu: 20 duplicate costume button handlers
**File:** `ui_scenes/settings/settings_menu.gd` lines 140-245

20 nearly identical functions (`_on_costume_button_1_pressed` through `_on_costume_button_10_pressed` and `_on_delete_1_pressed` through `_on_delete_10_pressed`) differ only in index. Should use a loop or parameterized connection.

### M41. Settings menu `_process` runs even when invisible
**File:** `ui_scenes/settings/settings_menu.gd` lines 194-199

The `_process` function checks mouse position every frame to set `hasMouse`, even when the settings menu is hidden.

### M42. Fragile parent traversal in mic select button
**File:** `ui_scenes/microphoneSelect/mic_select_button.gd` lines 11, 18

`get_parent().get_parent().get_parent().visible` -- three levels of `get_parent()`. If the scene hierarchy changes, this breaks silently.

### M43. Duplicate identical shaders
**Files:** `ui_scenes/spriteEditMenu/chain.gdshader`, `ui_scenes/selectedSprite/outline.gdshader`

These two shader files contain the exact same palette-cycling code. One should reference the other to avoid divergence during maintenance.

### M44. Push updates uses frame-based timing instead of delta
**File:** `ui_scenes/pushUpdates/push_updates.gd` line 31

`tick` increments by 1 per frame and compares against `240`. At 60 FPS this is ~4 seconds, but at 240 FPS the delay is only 1 second; at 30 FPS it is 8 seconds. Should use a delta-based accumulator.

### M45. No validation on window size restoration
**File:** `main_scenes/main.gd` line 87

`get_window().size = str_to_var(Saving.settings["windowSize"])` -- if the saved value is corrupted, `str_to_var` returns null, and assigning null to `window.size` could crash.

---

## 3. Minor Issues

### m1. Naming convention violations throughout
All files mix camelCase (`heldSprite`, `editMode`), snake_case (`_pan_offset`), and abbreviated names (`rdragStr`, `xFrq`, `wob`). GDScript convention is snake_case.

### m2. Magic numbers throughout
Hundreds of unexplained constants: `24.0` (gizmo radius), `0.0166` (1/60), `300` (ms threshold), `420` (blink logic), `4.0` (polygon epsilon), `0.1` (timer delay), `2` (texture filter), `1400` (window threshold), `432.0` (scroll speed), etc.

### m3. Variable `i` used as class member
**File:** `autoload/global.gd` line 20

`var i = 0` is a terrible name for a member variable tracking scroll selection index.

### m4. Unused variables
- `mouseOffset` in `spriteObject.gd` line 34: never read or written
- `delta` parameter in `drag()`: never used when `dragSpeed == 0`
- `_read_bytes` in `psd_parser.gd` lines 59-60: defined but never called
- `speed` uniform in `outline.gdshader`: computed `scroll` vector is never used

### m5. Per-frame array allocation in `talkBlink()`
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 288

Allocates `[0,10,20,30,1,21,12,32,3,13,4,15,26,36,27,38]` every single frame for every sprite. Should be a static constant.

### m6. Toggle uses string `"null"` instead of actual `null`
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 94

`var toggle = "null"` -- the default is the string "null", not null.

### m7. Redundant `ImageTexture.new()` immediately overwritten
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 122-123, 192-193

```gdscript
var texture = ImageTexture.new()
texture = ImageTexture.create_from_image(img)
```

The first line creates a texture that is immediately discarded.

### m8. `loadedImageData` never nulled after use
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 114

`loadedImage` is nulled after use but `loadedImageData` (potentially large base64 string) persists for sprite lifetime.

### m9. `open_site()` is dead code on desktop
**File:** `autoload/saving.gd` lines 126-136

On desktop, just prints a message. Should use `OS.shell_open(url)`.

### m10. String-based signal emission (GDScript 3 pattern)
**File:** `autoload/global.gd` lines 119-121

`emit_signal("startSpeaking")` instead of `startSpeaking.emit()`.

### m11. Self-referencing singleton pattern
**File:** `autoload/global.gd` lines 138, 161, 236

Inside the Global script, `Global.chain` is used instead of just `chain`. Inconsistently too -- line 138 uses `Global.chain` but line 145 uses just `chain`.

### m12. 10 duplicate layer button handlers
**File:** `ui_scenes/spriteEditMenu/sprite_viewer.gd` lines 238-320

Ten nearly identical functions differ only in array index. Should be a single parameterized function.

### m13. 10-branch match for layer selection
**File:** `ui_scenes/spriteEditMenu/sprite_viewer.gd` lines 322-345

Could be an array lookup.

### m14. `changeCostumeStreamDeck` match instead of int parse
**File:** `main_scenes/main.gd` lines 690-701

Could be `changeCostume(int(id))` with a bounds check.

### m15. Massive save/load/duplicate code duplication
**Files:** `main_scenes/main.gd`, `autoload/undo_manager.gd`

Sprite property-setting logic is duplicated in 3+ places. Each new property must be added in all locations.

### m16. No `class_name` on autoload scripts
Autoloads lack `class_name`, preventing type hints elsewhere. `psd_parser.gd` correctly has `class_name PSDParser`.

### m17. `defaultAvatarData.gd` embeds ~226KB inline
A `.tres` or `.json` file would be more appropriate.

### m18. Division by zero if `blinkChance` is 0
**File:** `autoload/global.gd` line 334

`rand.randi() % int(blinkChance)` crashes if `blinkChance` is 0. No setter validation.

### m19. Per-frame Rect2 allocation for button hit testing
**File:** `main_scenes/EditControls.gd` lines 36-69

Godot's built-in `mouse_entered`/`mouse_exited` signals would be more efficient.

### m20. Frame-rate dependent lerp on zoom label alpha
**File:** `main_scenes/main.gd` line 258

Lerp factor `0.02` is framerate-dependent. Should use delta-adjusted exponential decay.

### m21. Sprite list position ignores zoom
**File:** `main_scenes/main.gd` line 240

`spriteList.position.x = s.x - 233` doesn't account for `camera.zoom`.

### m22. Pan offset never resets on mode swap or load
**File:** `main_scenes/main.gd` lines 49-50

`_pan_offset` persists across mode changes and avatar loads. User may find avatar off-center.

### m23. Confusing toggle-based initialization
**File:** `main_scenes/main.gd` lines 3, 145, 282

`editMode` starts `true`, `swapMode()` toggles it to `false`. A clearer pattern would set mode explicitly.

### m24. Texture reassigned every frame
**File:** `main_scenes/main.gd` lines 186-198

`shadow.texture = Global.heldSprite.sprite.texture` triggers property change notifications every frame.

### m25. Inconsistent null checking patterns
Codebase mixes `!= null`, `is_instance_valid()`, `not file`, and bare truthiness checks. For freed nodes, only `is_instance_valid()` is safe.

### m26. No Delete keybinding for sprites
Input actions include add, replace, undo, etc. but no dedicated Delete key.

### m27. `control` input not mapped to Cmd on macOS
macOS users may expect Cmd+Z for undo rather than Ctrl+Z.

### m28. PSD parser: ASCII-only layer names
Unicode layer names stored in extra data sections are skipped.

### m29. `_input()` called for every sprite instance
Every spriteObject receives every input event. A centralized handler would be more efficient.

### m30. Signal connections never disconnected
Signals connected in `_ready()` are never disconnected. Problematic if scenes are reloaded.

### m31. No settings version number
**File:** `autoload/saving.gd`

No systematic migration path for old save files.

### m32. Path to file not sanitized on load
**File:** `main_scenes/main.gd` line 487

Crafted save file could set paths to overwrite arbitrary files when `saveImagesFromData()` is invoked.

### m33. Wobble shader typo `distortion_strengh`
**File:** `shader/wobble.gdshader` line 4

Uniform name `distortion_strengh` should be `distortion_strength`. This typo propagates to any code or material inspector referencing it.

### m34. Multiple UI nodes compete at z_index 4096
**File:** `main_scenes/main.tscn`

`MicInputSelect`, `SettingsMenu`, `Tutorial`, `Chain`, `Failed`, `ViewerArrows`, and `PushUpdates` all share z_index = 4096 (Godot's maximum for CanvasItem). Their relative draw order depends on tree order rather than explicit z, which is a maintenance hazard.

### m35. Unused `backImg` sampler and `scroll` variable in shaders
**Files:** `ui_scenes/spriteEditMenu/chain.gdshader`, `ui_scenes/selectedSprite/outline.gdshader`

`uniform sampler2D backImg: repeat_enable` is declared but never sampled. `scroll` is computed but never referenced. Dead code in both shaders.

### m36. `VolumeBar.gd` and `Sensitive.gd` poll Global every frame with no visibility check
**Files:** `ui_scenes/VolumeBar.gd`, `ui_scenes/volume/Sensitive.gd`

Both scripts run `_process` every frame to read `Global.volume` / `Global.volumeSensitivity`, even when the control panel is hidden.

### m37. Poorly named function `ohYeah()` in chain.gd
**File:** `ui_scenes/spriteEditMenu/chain.gd` line 13

Function provides no indication of its purpose. Should be named `updateLineAndPlug()` or similar.

### m38. `MicButtong` node name typo
**File:** `main_scenes/main.tscn`

Node likely intended to be `MicButton`.

### m39. Negative `custom_minimum_size` in push_updates.tscn
**File:** `ui_scenes/pushUpdates/push_updates.tscn` line 10

`custom_minimum_size = Vector2(0, -250)` -- negative minimum sizes have no defined behavior in Godot and may be silently clamped.

### m40. Undo image cache never bounded
**File:** `autoload/undo_manager.gd` line 15

`_image_cache` dictionary grows without limit, only cleared on full avatar rebuild. Long sessions with many sprite replacements accumulate stale entries.

---

## 4. Performance Concerns

### P1. `_snapshot()` encodes PNG to base64 on every save
**File:** `autoload/undo_manager.gd` line 30

`save_png_to_buffer()` is expensive. Base64 on top adds ~33% memory overhead. Storing raw `PackedByteArray` would save memory and CPU.

### P2. `_process` runs every frame even when not in edit mode
**File:** `autoload/global.gd` line 92

Input handling, scroll sprites, Z-order changes, and reparent mode logic runs every frame but is only relevant in edit mode.

### P3. PSD parser pixel loop is O(n) per channel per pixel in GDScript
**File:** `autoload/psd_parser.gd` lines 353-362

For a 4000x4000 layer, that is 16 million iterations in interpreted GDScript.

### P4. `get_tree().get_nodes_in_group("saved")` called repeatedly
Called in multiple files per frame chain. Each call traverses the entire scene tree.

### P5. Per-frame child iteration for outline width
**File:** `ui_scenes/selectedSprite/spriteObject.gd` lines 237-240

Iterates all grab area children every frame to set Line2D width. Width only needs updating when zoom changes.

### P6. `followShadow()` reassigns texture every frame
**File:** `main_scenes/main.gd` lines 186-198

Should only reassign when the held sprite changes.

### P7. Per-frame `talkBlink()` array allocation for every sprite
**File:** `ui_scenes/selectedSprite/spriteObject.gd` line 288

New array literal allocated every frame per sprite. Should be a static constant.

---

## 5. Security Concerns

### S1. `str_to_var()` with untrusted save data (see C1)
Can instantiate arbitrary Godot objects from crafted strings.

### S2. JavaScript injection in web builds (see C11)
Direct string concatenation into `eval()` calls.

### S3. No path sanitization on avatar file paths
Crafted save files could overwrite arbitrary files via `saveImagesFromData()`.

### S4. Stream Deck allows arbitrary scene switching from network input
**File:** `addons/godot-streamdeck-addon/singleton.gd` lines 60-65

WebSocket accepts scene change commands with arbitrary paths from localhost.

---

## 6. Architecture & Anti-Patterns

### A1. God Object: `global.gd`
Manages microphone creation, audio detection, speech detection, cursor tracking, blink state, sprite selection, sprite linking, scroll cycling, Z-order changes, reparent mode, origin mode, keyboard shortcuts, file refresh, image saving, and error display. At least 8 distinct responsibilities.

### A2. Tight coupling via global mutable state
All scripts reference each other directly through globals. Scene nodes are set by those nodes in their `_ready()` functions, creating temporal coupling.

### A3. Save/load code triplicated
Sprite property serialization exists in save, load, duplicate, undo snapshot, and undo restore. Each new property requires changes in 5+ locations.

### A4. No signals for state changes
`Global.heldSprite`, `Global.speaking`, `Global.reparentMode`, etc. are all polled via direct variable reads. Signal-based approach would be more decoupled.

### A5. Wobble/animation timing is framerate-coupled
`tick` increments once per `_process` call, making `sin(tick * freq)` dependent on framerate rather than real time.

---

## 7. Summary Statistics

| Severity | Count |
|----------|-------|
| Critical | 12 |
| Major    | 45 |
| Minor    | 40 |
| Performance | 7 |
| **Total** | **104** |

### Top Priority Fixes

1. **C7** -- Integer division in `drag()` completely breaks a user-facing feature. Fix: change `1/dragSpeed` to `1.0/dragSpeed`.
2. **C8/C9** -- Parent lookup crash and hardcoded frame time. These affect core functionality.
3. **C2/C3/C6** -- Null dereference crashes in autoloads. Guard all global references.
4. **M10** -- `changeCollision()` duplicate line. Simple one-character fix (`monitorable` -> `monitoring`).
5. **M11** -- `remakePolygon()` wrong dimensions. Fix: `Vector2(imageSize.x / frames, imageSize.y)`.
6. **M2** -- `costumeLayers` padding. Fix: `while sprite.costumeLayers.size() < 10: sprite.costumeLayers.append(1)`.
7. **M33** -- Duplicate sprite shared array. Fix: add `.duplicate()` to costumeLayers assignment.
8. **C9/M17** -- Use `delta` for all physics calculations instead of constant values and unscaled lerp factors.
