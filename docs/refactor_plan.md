# Refactor Execution Plan

> Updated: 2026-08-17 — Phases 0–8 established the safety baseline; the
> maintainability completion program continues through Phases 9–16.

The refactor proceeds in small, auditable commits. Each phase must preserve
save compatibility and user-facing behavior unless its change is explicitly
documented. A phase is complete only after targeted tests, the full test gate,
performance review where relevant, documentation updates, and a focused commit.

Progress: Phases 0–13 are complete. Phase 14 is next. Completed phases remain
covered by the cumulative production-scene, isolated, native, performance, and
standalone export gates.

## Developer handoff

> Updated: 2026-08-17 — standalone continuation guide after Phase 13

This file is the canonical execution and handoff plan. A developer taking over
should start on branch `refactor`, read `AGENTS.md`, then read
`docs/architecture_guide.md`, `docs/quality_baseline.md`, and
`docs/save_format.md`. The supported engine is Godot 4.6.3; do not validate a
phase using a different minor release. The local phase sequence currently ends
with commits titled `Phase 9: add production avatar regression harness`,
`Phase 10: define application state boundaries`, `Phase 11: complete main scene
decomposition`, and the Phase 12 sprite-runtime commit.
The next local commit is the Phase 13 UI-componentization commit containing
this handoff update.
Confirm with `git log --oneline` because the remote branch may lag local work.

Before editing:

1. Run `git status --short` and preserve unrelated or untracked user files.
2. Run the full gate once to distinguish inherited failures from new ones.
3. Inspect the production scene and all callers before moving a method. Keep the
   existing public facade until every caller and real-scene test has migrated.
4. Add behavior tests before or alongside each extraction. Source-string tests
   are architectural guards, not substitutes for real instantiated scenes.
5. Update the architecture guide with a dated, targeted note for every new
   system or changed data flow. Complete each phase as one focused commit.

Required local gates (set `GODOT_BIN` to an official Godot 4.6.3 executable):

```bash
GODOT_BIN=/absolute/path/to/godot ./scripts/run_tests.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_performance.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_export_smoke.sh
git diff --check
```

`run_tests.sh` must pass both the production application runner and the isolated
suite, then the active NDI teardown smoke. `run_performance.sh` must pass both
microbenchmarks and complete 100/250-layer avatar loads. The export smoke must
build and launch the standalone resource pack. Cross-platform CI remains the
authority for Linux and Windows after a push.

Current structural baseline:

- `main_scenes/main.gd`: 597 lines; scene lifecycle/signal facade backed by five
  injected controllers.
- `ui_scenes/selectedSprite/spriteObject.gd`: 951 lines; scene-facing layer
  facade backed by pure policies plus visual, collision, animation, and wiggle
  services.
- UI scene facades: `ui_scenes/spriteList/viewer.gd` (695 lines/38 methods),
  `ui_scenes/spriteEditMenu/sprite_viewer.gd` (697/27), and
  `ui_scenes/settings/settings_menu.gd` (123/7). Feature components are all
  smaller than 500 lines.
- Latest Phase 13 gate: 454 real-scene assertions, 794 isolated assertions,
  271.15 ms for 100-layer load, 465.60 ms for 250-layer load, 3.66 µs per
  active 100-layer animation frame, and 220.58 ms for ten complete wiggle
  auto-fits on the baseline M1 Max. All budgets, NDI teardown, and standalone
  macOS pack export pass.

Non-negotiable compatibility rules:

- Preserve the versioned save schema, unsigned 32-bit sprite IDs, ten-slot
  costume arrays, legacy idle-wobble migration, and existing facade method
  names until callers are deliberately migrated.
- `Global` remains the canonical owner of `main`, `spriteEdit`, `spriteList`,
  `mouse`, and `chain`; use its attach/detach and public state APIs.
- Production enumeration uses `Global.sprite_nodes()`/`SpriteRegistry`; the
  `"saved"` group remains only for scene/debugger compatibility.
- Selection uses `Global.select_sprite()`/`clear_selection()`. Canvas picking
  uses `intersect_point()` and the centralized three-parent hit resolver.
- Programmatic decorative `ColorRect` nodes must ignore mouse input. Hidden edit
  UI must remain process-disabled in player mode, and layer collision must
  remain disabled there.
- Set `_skip_ready_reparent` before inserting a duplicate into the scene tree.
  `_ready()` runs synchronously during `add_child()`.
- Optional native integrations must compile out or fail closed when absent, and
  every worker/native lifecycle must join or disconnect during teardown.

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

## Phase 9 — Real-application regression harness

- Exercise the production main and sprite scenes with isolated persisted and
  device state rather than relying only on source contracts and pure helpers.
- Fixture-test unsigned IDs, hierarchy reconstruction, legacy idle motion,
  every costume, ancestor visibility, rejected loads, and save/load round trips.
- Benchmark complete 100- and 250-layer loads, including decode, collision,
  scene assembly, hierarchy, costume application, and layer-list refresh.

> Completed: 2026-08-17 — `tests/integration/avatar_scene_runner.tscn`
> launches the real application graph under `--avatar-integration-test` while
> `Saving.is_isolated_session()` prevents host settings, recovery files,
> microphones, and external devices from influencing the run. Two versioned
> fixtures reproduce the ID/hierarchy/sway/costume regressions and schema
> rejection. The runner passes 378 behavioral assertions; the isolated suite
> passes 652. Production load budgets and exact artifacts now cover 100 and 250
> layers. The macOS NDI smoke also allows 120 rendered frames before teardown so
> Godot 4.6.3 finishes its asynchronous Metal pipeline callback before the test
> audits the extension lifecycle.

## Phase 10 — Explicit application boundaries

- Separate selection, sprite lookup, input state, avatar session state, and UI
  notification responsibilities behind narrow Godot-native APIs.
- Keep `Global` as the canonical owner of shared scene-node references while
  moving feature behavior behind focused methods and services.
- Centralize the required three-level Area2D-to-sprite traversal in one helper.

> Completed: 2026-08-17 — `SelectionState` owns selected-layer and repeated-hit
> state behind `Global.select_sprite()`/`clear_selection()`, while
> `SpriteRegistry` is now the production enumeration boundary as well as the ID
> index. All shared scene references use paired attach/detach methods without
> changing their established `Global` location. The Area2D parent walk exists
> only in `sprite_from_hit_area()`, and input modes, key capture, and user
> notifications expose purpose-named public methods. Pure/source contracts and
> production-scene assertions cover the boundaries; the cumulative gate passes
> 390 application assertions and 686 isolated assertions on Godot 4.6.3.

## Phase 11 — Main-scene completion

- Extract transactional avatar assembly, import-result application, edit
  commands, costume orchestration, and dialog presentation from `main.gd`.
- Leave the scene script responsible for lifecycle wiring and delegation.

> Completed: 2026-08-17 — `AvatarController` now owns avatar assembly,
> validation, save-data construction, edit commands, hierarchy reconstruction,
> costumes, and decode-worker shutdown. `ImportController` owns PSD/APNG/PNG
> pipelines, bounded worker preparation, dialogs, review application, and
> cancellation, while the pure `ImportMatcher` makes duplicate-name decisions
> deterministic. The compatibility-facing `main.gd` fell from roughly 1,660 to
> 597 lines. The production audit also fixed duplicated layers setting their
> `_skip_ready_reparent` guard after `add_child()`, when `_ready()` had already
> scheduled its timer. The cumulative Godot 4.6.3 gate passes 401 real-scene
> assertions, 710 isolated assertions, performance budgets, NDI teardown, and
> standalone macOS pack export.

## Phase 12 — Sprite runtime decomposition

- Separate visibility policy, hierarchy state, animation, wiggle runtime,
  wiggle geometry, visual synchronization, and collision coordination.
- Retain `spriteObject.gd` as the scene-facing facade while behavior migrates.

> Completed: 2026-08-17 — `spriteObject.gd` fell from 1,573 to 951 lines.
> `SpriteVisibilityPolicy` and `SpriteHierarchy` are pure deterministic rules;
> `SpriteVisualRuntime` owns diffuse/normal/blend/depth synchronization;
> `SpriteCollisionRuntime` owns shape replacement and active-state coordination;
> and wiggle is split into pure geometry, live node/editor lifecycle, and the
> existing appendage simulation. `LayerAnimator` remains the animation boundary.
> Stable sprite methods continue as scene/UI/persistence facades. Replacement
> now synchronizes new image dimensions before visual/wiggle/collision rebuild.
> Pure tests
> cover visibility, cycle-safe hierarchy, path tracing/projection/coverage, and
> width interpolation; the production runner exercises actual appendage
> enable/disable and different-size replacement. The cumulative gate passes 410 real-scene and 740 isolated
> assertions, all performance budgets, NDI teardown, and macOS pack export.

## Phase 13 — UI componentization

- Split the left sidebar, right sidebar, and settings form into focused panels.
- Centralize binding and enabled-state rules and test panels as real scenes.

Handoff execution order:

1. Inventory every method, signal, and cross-panel call in the three hotspot
   files before editing. Record the stable public surface used by main, Global,
   sprite rows, physics/blend/animation panels, and tests.
2. Extract the right sidebar first: layer-tree model/rebuild, costume strip,
   details controls, tracking controls, and container resize/layout. Keep
   `viewer.gd` as the scene facade and retain `Global.spriteList` there.
3. Extract the left sidebar by property group: transform/motion, talk/blink,
   animation, normal-map/file actions, and selection enabled-state. Keep
   `Global.spriteEdit` on the facade.
4. Split settings by tab while keeping persistence writes and input-capture
   coordination explicit. Reuse `FormUI`, `SidebarUI`, `TabBar`, and `MenuBar`;
   do not create a second style/bounds system.
5. For each component, instantiate the actual scene in tests and exercise
   selection/no-selection, edit/player, narrow-window, and callback behavior.

Acceptance: no extracted panel resolves private state on another panel; facade
files primarily construct/wire components; each hotspot is below 700 lines or
has a documented reason; no hidden panel processes on the player page; all
current UI and release gates remain green.

> Completed: 2026-08-17 — The right sidebar delegates hierarchy/filter/scroll,
> tracking, and layer details to `LayerTreeController`, `EyeTrackingPanel`, and
> `LayerDetailsPanel`; the left delegates selection presentation, normal-map
> actions, and rotation texture construction to focused components alongside
> the existing animation panel. Its retired 3D previews and superseded hidden
> controls were removed from the production scene. Settings now has one
> injected component per Audio, Display, Motion, Hotkeys, and Output tab while
> `settings_menu.gd` retains its public frame/input facade. Source contracts
> enforce the 700-line sidebar ceiling, injected dependency direction, and
> stable facade calls. Real-scene tests instantiate all five settings bodies,
> exercise every tab, selection/no-selection, and edit/player processing; pure
> tests cover layer flattening/filtering/indentation and tracking scope/target
> rules. The cumulative Godot 4.6.3 gate passes 454 real-scene assertions and
> 794 isolated assertions, performance budgets, active NDI teardown, and the
> standalone macOS pack export. Stop here before Phase 14 unless explicitly
> authorized to continue.

## Phase 14 — Mutation, undo, and input boundaries

- Route sprite mutations through canonical commands with undo capture.
- Remove UI knowledge from `UndoManager` and consolidate device/key commands.
- Retain the project convention that scene references live on `Global`, while
  reducing direct cross-feature method calls to narrow coordination points.

Handoff execution order:

1. Enumerate every `UndoManager.save_state*()` call and every direct persistent
   sprite-property assignment in UI/input code.
2. Introduce narrow commands for single-property, continuous drag/slider,
   structural hierarchy, image replacement, and bulk costume/import mutations.
   A command owns the before/after snapshot boundary exactly once.
3. Remove `UndoManager` calls into UI refresh methods; emit a state-restored
   notification or let the scene coordinator refresh registered consumers.
4. Route foreground and optional background key/device input through one command
   decoder while preserving current focus guards and Stream Deck behavior.

Acceptance: user mutations are undoable through one canonical path, continuous
input produces one logical history entry, undo has no UI knowledge, save/load
and all ten costumes round-trip, and production tests cover command undo/redo.

> Completed: 2026-08-17 — `autoload/domain/mutation_commands.gd` is the single
> canonical mutation path, with narrow commands for discrete single-property,
> continuous drag, structured-field, structural, and awaited bulk work; each
> owns its snapshot boundary once and aborts to discard a no-op entry.
> All 74 former `save_state()` call sites were migrated, and a source contract
> fails the build if any production file outside the command layer opens a
> transaction. `UndoManager` gained `begin`/`commit`/`abort`, gesture-keyed
> continuous edits, and a `state_restored(scope)` signal; every scene and
> sidebar consequence of a restore moved to `AvatarController.on_state_restored()`.
> Foreground, background, and Stream Deck input share the pure decoder in
> `autoload/input/input_commands.gd`, preserving the existing focus guards while
> stateful tap-versus-hold timing stays in `Global`. Four defects surfaced by the
> migration were fixed: clip rename captured no history, restore un-hid
> eye-hidden layers, no-op commands left dead entries, and restored sprites
> reparented on a deferred timer that leaked at exit. The cumulative Godot 4.6.3
> gate passes 476 real-scene assertions and 878 isolated assertions, performance
> budgets, active NDI teardown, and the standalone macOS pack export, with no
> leaked ObjectDB instances. Stop here before Phase 15 unless explicitly
> authorized to continue.

## Phase 15 — Performance and lifecycle qualification

- Profile load, costume, hierarchy, sidebar, animation, undo-memory, import
  cancellation, and shutdown workloads in the decomposed architecture.
- Optimize measured regressions and repeat native lifecycle smokes.

Add repeatable measurements for costume switching, hierarchy rebuild, sidebar
refresh while visible/hidden, command undo memory, wiggle frame cost, import
cancellation, and repeated application shutdown. Compare exact artifacts to the
Phase 12 numbers above; optimize only measured regressions. Run repeated active
NDI teardown and missing-extension paths on every available host OS.

Acceptance: every workload has a generous algorithmic smoke ceiling and a JSON
trend value, 100/250-layer loads and active animation do not materially regress,
no ObjectDB/thread/native leaks remain, and player mode performs no hidden edit
work.

> Completed: 2026-08-17 — `tests/performance/lifecycle_runner.tscn` measures all
> seven workloads against a 100-layer production rig, each with a smoke ceiling
> and a trend value in `.artifacts/performance-lifecycle.json`, and the release
> contract fails if a workload loses either. No workload regressed: animation,
> validation, lookup, ribbon auto-fit, and 100/250-layer loads all improved or
> held against Phase 12/13, within a run-to-run variance of roughly 15%.
> Building the gate exposed two measurement bugs that had been reporting
> success (paced wall-clock frames measuring the frame interval rather than the
> work, and un-awaited `updateData()` loops coalescing 50 rebuilds into one) and
> one real defect: a scene torn down during an avatar load stranded the load
> coroutine and leaked a `GDScriptFunctionState`. Loads are now explicitly
> cancellable through `shutdown()`, and both the production runner and the
> lifecycle gate exit with no leaked ObjectDB instances. Player mode is proved
> free of hidden edit work structurally, by `can_process()` on both sidebars,
> because timing at this layer count cannot separate the signal from noise.
> Active NDI teardown passed three additional macOS runs; Windows and Linux
> hosts were unavailable, so that half of the native check remains for CI.
> Stop here before Phase 16 unless explicitly authorized to continue.

## Phase 16 — Completion audit

- Remove compatibility facades and dead paths, resolve or document warnings,
  refresh the codebase evaluation, and run the full cross-platform release
  matrix from a clean checkout.
- Declare the refactor finished only when the quantitative and architectural
  acceptance criteria in this plan and the architecture guide remain green.

Audit every production script for dead facades, duplicate policies, private
cross-feature calls, unbounded file/thread work, stale comments, warnings, and
unowned lifecycle resources. Remove a facade only after repository-wide caller
search and real-scene coverage. Re-run save fixtures from every supported legacy
shape, clean-checkout release gates, and Linux/macOS/Windows CI exports.

The refactor is finished only when all phases are committed, the worktree is
clean apart from known user files, the full local and cross-platform matrix is
green, architecture/save/dependency/contributor docs match the code, every
remaining oversized file has one coherent responsibility, and a fresh developer
can make a typical feature change without editing unrelated subsystems.
