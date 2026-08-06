# Refactor Execution Plan

> Updated: 2026-08-06 — Phase 2 runtime-service completion

The refactor proceeds in small, auditable commits. Each phase must preserve
save compatibility and user-facing behavior unless its change is explicitly
documented. A phase is complete only after targeted tests, the full test gate,
performance review where relevant, documentation updates, and a focused commit.

Progress: Phases 0–2 are complete. Phase 3 (main scene decomposition) is next.
Completed phases remain covered by the cumulative test and performance gates.

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

## Phase 4 — Sprite domain behavior

- Separate sprite data, rendering, collision, animation, hierarchy, and editor
  interaction responsibilities currently concentrated in `spriteObject.gd`.
- Consolidate duplicate create/duplicate/restore property maps.
- Correct frame-rate, hierarchy, collision, and ownership fragility under tests.

## Phase 5 — UI and input components

- Decompose oversized panels and repeated control-building/styling code.
- Centralize selection guards, modal behavior, input routing, and reusable UI
  primitives without silently changing established interaction conventions.
- Add scene/component tests for callbacks and state synchronization.

## Phase 6 — Importers and native integrations

- Harden PNG/APNG/PSD import boundaries, thread ownership, cancellation, and
  size/section validation.
- Audit Stream Deck and NDI lifecycle/error handling on every supported OS.
- Resolve or isolate the known godot-ndi macOS teardown defect before release.

## Phase 7 — Performance and memory

- Profile representative avatar workloads and optimize measured bottlenecks.
- Reduce unnecessary per-frame polling/writes, repeated tree scans, geometry
  rebuilds, allocations, and full-image undo snapshots where evidence supports it.
- Compare CI performance artifacts to Phase 0 and add focused regression gates.

## Phase 8 — Final architecture and release hardening

- Remove dead code, temporary compatibility paths, obsolete assets, and stale
  terminology after all callers have migrated.
- Complete the architecture map, dependency inventory, contributor workflows,
  and save-format documentation.
- Run the full cross-platform test/export/smoke matrix and a final code audit.
