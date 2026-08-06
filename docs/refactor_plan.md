# Refactor Execution Plan

> Updated: 2026-08-06 — all planned refactor phases complete

The refactor proceeds in small, auditable commits. Each phase must preserve
save compatibility and user-facing behavior unless its change is explicitly
documented. A phase is complete only after targeted tests, the full test gate,
performance review where relevant, documentation updates, and a focused commit.

Progress: Phases 0–8 are complete. Completed phases remain covered by the
cumulative test, performance, and standalone export gates.

## Phase 0 — Baseline and safety rails

- Standardize on Godot 4.6.3 and pin native dependencies.
- Remove duplicate/obsolete extensions and versioned build intermediates.
- Establish cross-platform CI, isolated tests, source contracts, and
  repeatable performance smoke budgets.
- Capture dependency risks and the initial performance reference.

## Phase 1 — Persistence and data safety

- Introduce explicit save/settings schemas and typed conversion helpers.
- Replace unsafe or duplicated deserialization, validate untrusted files, and
  preserve migrations for existing avatars/settings.
- Make writes atomic and surface actionable errors.
- Add fixture-driven round-trip, migration, malformed-input, and failure tests.

## Phase 2 — Runtime state and autoload boundaries

- Reduce `Global` to well-defined application state and lifecycle services.
- Isolate microphone/input orchestration, remove uncontrolled coroutine and
  child-lifetime behavior, and add null-safe startup/shutdown paths.
- Define narrow contracts for autoload communication while preserving the
  project's polling model where it remains intentional.

## Phase 3 — Main scene decomposition

- Turn `main.gd` into a coordinator rather than a multi-purpose subsystem.
- Extract avatar lifecycle, import orchestration, viewport/window behavior,
  editing commands, and file workflows one responsibility at a time.
- Add integration tests around each extracted boundary before moving the next.

> Completed: 2026-08-06 — Capture/FFmpeg, viewport/window, and
> save/session-recovery lifecycles now live in injected, independently testable
> controllers. `main.gd` fell from roughly 2,900 to 2,037 lines while preserving
> its scene-signal interface. The test harness now treats isolated Godot script
> errors as failures as well as checking the production recovery import.

## Phase 4 — Sprite domain behavior

- Separate sprite data, rendering, collision, animation, hierarchy, and editor
  interaction responsibilities currently concentrated in `spriteObject.gd`.
- Consolidate duplicate create/duplicate/restore property maps.
- Correct frame-rate, hierarchy, collision, and ownership fragility under tests.

> Completed: 2026-08-06 — A canonical `SpriteState` compatibility map now
> serves save, load, undo/redo, and duplicate flows, removing roughly 400 lines
> of parallel property copying. Structured values are deep-cloned and legacy
> costume arrays normalize to ten slots. Collision construction moved out of
> `spriteObject.gd`; transparent-image fallback and rectangular animated-frame
> sizing are tested. `main.gd` is now 1,842 lines and `undo_manager.gd` 267.

## Phase 5 — UI and input components

- Decompose oversized panels and repeated control-building/styling code.
- Centralize selection guards, modal behavior, input routing, and reusable UI
  primitives without silently changing established interaction conventions.
- Add scene/component tests for callbacks and state synchronization.

> Completed: 2026-08-06 — Both oversized sidebars now share one `SidebarUI`
> primitive for slider resources, click-through decoration, resize bounds, and
> safe width clamping. The global wheel router and sprite-selection cursor use
> the same editor-chrome hit test, eliminating duplicated panel geometry.
> Component contracts verify mouse filters, style transitions, narrow-window
> sizing, resize margins, and input-routing regions.

## Phase 6 — Importers and native integrations

- Harden PNG/APNG/PSD import boundaries, thread ownership, cancellation, and
  size/section validation.
- Audit Stream Deck and NDI lifecycle/error handling on every supported OS.
- Resolve or isolate the known godot-ndi macOS teardown defect before release.

> Completed: 2026-08-06 — APNG and PSD parsing now share explicit file,
> section, dimension, count, and decoded-memory budgets; validate every binary
> boundary before access; and support cooperative shutdown cancellation. Main
> owns and joins all three import thread lifecycles. Stream Deck packets/config
> and NDI crop/output geometry have pure validated boundaries, while their
> sockets, signals, timers, and native nodes tear down explicitly. The open
> upstream godot-ndi macOS defect remains isolated from deterministic tests by
> recovery-mode production import and the native-free isolated test project;
> production behavior remains documented as a release risk rather than being
> concealed by the application code.

> Updated: 2026-08-06 — Follow-up isolation traced the macOS crash to the
> extension's `ViewportTextureRouter` disconnecting after `RenderingServer`,
> plus queued asynchronous texture callbacks during active output. PNGTuberPlus
> now carries the MPL source patch, rebuilt Godot 4.6 universal macOS binaries,
> audited digests, and a native extension teardown smoke. The former release
> risk is resolved locally while upstream issue 44 remains open.

## Phase 7 — Performance and memory

- Profile representative avatar workloads and optimize measured bottlenecks.
- Reduce unnecessary per-frame polling/writes, repeated tree scans, geometry
  rebuilds, allocations, and full-image undo snapshots where evidence supports it.
- Compare CI performance artifacts to Phase 0 and add focused regression gates.

> Completed: 2026-08-06 — A live sprite registry replaces per-frame ID group
> lookups and the layer-list's quadratic target-badge scans; hierarchy rebuilds
> use direct maps. Idle animation and unchanged visual/UI paths avoid allocation
> and redundant property writes. PSD preparation is bounded by Godot's worker
> pool instead of layer-count OS threads. Undo image caches prune dead or
> replaced references while snapshots retain the exact references required for
> history. A 250-layer/60-frame target workload improved from 316.09 ms for the
> old scan model to 3.67 ms indexed (86.1×), and new worker/registry/cache/source
> contracts run in the cumulative suite.

## Phase 8 — Final architecture and release hardening

- Remove dead code, temporary compatibility paths, obsolete assets, and stale
  terminology after all callers have migrated.
- Complete the architecture map, dependency inventory, contributor workflows,
  and save-format documentation.
- Run the full cross-platform test/export/smoke matrix and a final code audit.

> Completed: 2026-08-06 — Generated font caches and obsolete NDI demo media,
> linker intermediates, dead version labels, unsupported native mappings, and
> stale terminology were removed. Optional native background capture no longer
> prevents the main scene from loading, and NDI scene ownership is deterministic
> during recursive teardown. Product/export metadata and an explicit indirect
> resource manifest now produce a standalone production pack. The architecture
> map, dependency inventory, save-format contract, and contributor workflow are
> complete and enforced by release tests. The final local audit passed 504
> assertions, all performance budgets, and a production pack export/launch;
> CI owns the same resource-pack smoke across Linux, macOS, and Windows.
