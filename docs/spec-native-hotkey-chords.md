# Spec: Native hotkey chords

## Objective

Add native configurable hotkey combinations to PixelLab Studio so a user can
bind actions such as `Shift+2` without AutoHotkey or other external software.
The feature covers costume switching, per-layer visibility toggles, and
key-triggered animation clips because all three use the same background input
pipeline.

Acceptance behaviour:

- A binding contains zero or more modifiers (`Ctrl`, `Alt`, `Shift`, `Meta`)
  and exactly one primary keyboard key.
- Matching is exact for modifiers: `2` and `Shift+2` are distinct bindings.
- Other held non-modifier keys are ignored, so holding `W` in a game does not
  prevent `Shift+2` from firing.
- A binding fires once when it becomes active and can fire again after release.
- Existing single-key strings (`"1"`, `"F13"`, and similar) remain valid.
- Binding capture waits for a primary key instead of saving `Shift` immediately.
- Display and persistence use a stable canonical order, for example
  `Ctrl+Alt+Shift+2`.
- Background/unfocused input continues to use the existing native
  `BackgroundInputCapture` extension.

## Tech stack

- Godot 4.6 / GDScript
- Existing native `BackgroundInputCapture` GDExtension
- Existing JSON-backed settings and avatar persistence
- No new runtime dependencies

## Commands

From the repository root, with a Godot 4.6 console binary available as
`godot4`:

```powershell
godot4 --headless --path . --script test/hotkey_binding_test.gd
godot4 --headless --path . --editor --quit
godot4 --headless --path . --export-release "Windows Desktop" build/PixelLabStudio.exe
```

The first two commands are required for the feature. The Windows export is run
when the local export templates and native libraries are available.

## Project structure

- `autoload/hotkey_binding.gd`: pure canonicalization and matching logic.
- `main_scenes/main.gd`: background key state, capture, edge detection, and
  dispatch to costume/visibility/animation consumers.
- `test/hotkey_binding_test.gd`: headless regression tests.
- `docs/keyboard_shortcuts.md`: user-facing chord documentation.

## Code style

Follow existing GDScript conventions and keep the matching logic pure:

```gdscript
var binding := HotkeyBinding.from_pressed(pressed_keys, newly_pressed_keys)
if HotkeyBinding.is_active(binding, pressed_keys):
	activated_bindings.append(binding)
```

Use tabs for indentation, descriptive camelCase for existing `main.gd` state,
and snake_case inside the new utility to match modern Godot APIs.

## Testing strategy

Small headless tests cover:

- canonical modifier ordering;
- single-key backward compatibility;
- distinction between `2` and `Shift+2`;
- left/right modifier normalization where exposed by Godot key names;
- ignoring unrelated held gameplay keys;
- malformed or modifier-only bindings not activating;
- capture choosing the newly pressed primary key.

An integration check imports the complete Godot project headlessly. A manual
Windows check should bind `Shift+2`, minimize the app, and verify one costume
change per press while another non-modifier key is held.

## Boundaries

- Always: preserve existing saved bindings, use the existing native background
  input extension, test the pure logic before integration, and document the UI.
- Ask first: add dependencies, change the native extension, change save-file
  schemas, or broaden beyond keyboard chords.
- Never: require AutoHotkey, suppress keys sent to games, install a keyboard
  driver, or commit generated exports/native build artifacts.

## Success criteria

- `Shift+2` can be captured and displayed natively.
- Pressing `2` alone does not fire a `Shift+2` action, and pressing `Shift+2`
  does not fire an action bound to `2`.
- Holding `W` while pressing `Shift+2` still fires `Shift+2` once.
- Costume, visibility, and animation bindings share the same behaviour.
- Old single-key settings load and work unchanged.
- Regression tests pass and the project imports without script errors.

## Open questions

- Controller or multi-primary-key chords (for example `Q+E`) are intentionally
  out of scope.
- Modifier-only bindings remain readable for backward compatibility but cannot
  be newly captured, because capture must wait to distinguish `Shift` from
  `Shift+2`.
