# CLAUDE.md — PNGTuberPlus

## Project

PNGTuberPlus is a Godot 4.6 PNGTuber avatar app. The supported patch release is Godot 4.6.3. Entry point: `main_scenes/main.tscn`.

## Architecture Guide

See `docs/architecture_guide.md` for the full architecture reference. **Keep it up to date**: when making structural changes (new files, new systems, changed data flow, new UI panels, modified input handling), update the relevant sections of the architecture guide. Never replace entire sections wholesale — make atomic, targeted edits. Date-stamp all updates (e.g., `> Updated: 2026-02-15 — description`).

## Key Autoloads

- `Global` — central state (selection, mic, input, modes)
- `Saving` — JSON persistence, settings
- `UndoManager` — snapshot-based undo/redo
- `DefaultAvatarData` — built-in default avatar

## Conventions

- GDScript, mixed camelCase/snake_case (existing convention, don't unilaterally rewrite)
- UI backgrounds (`ColorRect`) created in `_ready()` must set `mouse_filter = MOUSE_FILTER_IGNORE` to avoid blocking canvas clicks
- Sprite click detection uses `PhysicsDirectSpaceState2D.intersect_point()` (not cached `get_overlapping_areas()`)
- Node references stored on `Global` singleton: `Global.main`, `Global.spriteEdit`, `Global.spriteList`, `Global.mouse`
- State is polled each frame via `_process()` rather than signal-driven

## Important Gotchas

- `_unhandled_input` is used for canvas clicks — any Control node with `MOUSE_FILTER_STOP` will swallow events before they reach it
- Parent lookup from Area2D to sprite root is 3 levels: `area.get_parent().get_parent().get_parent()`
- The `"saved"` group contains all sprite objects for enumeration

## Verifying changes

- When a change should produce an **obvious visible result** (a UI element moves,
  a menu appears, a layout reflows, motion stops), **ask the user to test it**
  rather than trying to capture it yourself. Screenshots of the running app are
  slow and unreliable here (the window often lands on another display or space),
  and the user has the app open already. Headless measurement is still the right
  tool for logic, layout numbers and regression tests; it is reaching for a
  picture of the app that wastes the round-trip.
- After a script change, the running app keeps the old behaviour until it is
  restarted. Say so when asking the user to test.

## Debugging

- When the user reports a crash or error, **always ask for the exact error text** (message + script:line) before attempting a fix. Don't guess from symptoms alone — Godot runtime errors point you at the right line, and the wrong fix wastes a round-trip. Only proceed without it if the user has already given enough context to pin the cause.
