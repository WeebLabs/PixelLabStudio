# Quality Baseline

> Updated: 2026-08-17 — Phase 13 UI-componentization gate

This document records the reproducible safety rails used throughout the
refactor. Exact timing artifacts are written to `.artifacts/` and retained by
CI; they are intentionally not committed.

## Supported toolchain

| Component | Baseline |
| --- | --- |
| Godot | 4.6.3 stable (`7d41c59c4`) |
| Renderer | GL Compatibility |
| `godot-cpp` | `58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74` (4.6-stable API sync) |
| godot-ndi | v1.2.6 (`d99e749`) plus the local macOS issue 44 patch; upstream archive SHA-256 `0ffaf8255a268e9408c344187143b612d37ee5147c1c752b426d6a6b95a4ffe7` |

CI downloads official Godot builds for Linux, macOS, and Windows and verifies
their SHA-256 digests before executing any project code. The PSD extension's
macOS binary is rebuilt against the pinned `godot-cpp` revision. Build
intermediates are ignored and are no longer versioned.

## Quality gates

Run the same checks locally with:

```bash
GODOT_BIN=/absolute/path/to/godot ./scripts/run_tests.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_performance.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_export_smoke.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_release_checks.sh
```

`run_tests.sh` performs a Godot 4.6 recovery-mode import to compile production
scripts, runs an isolated production-scene avatar lifecycle test, then runs unit
and contract tests in a minimal project. `Saving.is_isolated_session()` prevents
user settings, recovery state, microphones, and external devices from affecting
the production-scene run; the smaller project keeps pure tests independent of
optional native runtimes. When a macOS NDI runtime is installed, the same gate also
loads the bundled extension in a clean project and requires clean idle and
rendered active-output shutdown, directly covering both native teardown paths.

`run_export_smoke.sh` exports the host production preset as a resource pack,
changes to the artifact directory, and launches that pack without access to
source-tree fallbacks or persisted developer settings. It catches missing
indirect scripts/scenes, parse or shader compilation errors, and startup
lifecycle faults. `run_release_checks.sh` composes all local gates. CI runs the
tests and export smoke on Linux, macOS, and Windows and records performance on
Linux; native integrations still require a full exported-build check on each
affected platform.

`run_performance.sh` benchmarks repeatable CPU paths: animation
evaluation at 1/10/50/100 layers, 100-layer avatar JSON serialization,
100-layer schema validation/migration, runtime blink/microphone state updates,
alpha-to-polygon image geometry, one million binary import-boundary checks,
one million indexed sprite lookups, and indexed-versus-quadratic eye-target
resolution. It stores exact results and enforces broad smoke ceilings of 15 microseconds per
100-layer animation layer-frame, 500 ms for serialization, 3,000 ms for schema
validation, 1,000 ms per 100,000 runtime-service updates, and 200 ms for image
geometry, 2,000 ms each for one million import and sprite-registry validations,
and 100 ms for 15,000 indexed eye-target lookups. A second production-scene
artifact measures complete 100- and 250-layer avatar loads with broad 5,000 ms
and 12,000 ms smoke ceilings. Phase work should compare
the same CI-runner artifact before and after changes; a ceiling is not a
performance target.

## Phase 0 measurement

Measured on macOS with Godot 4.6.3:

| Workload | Result |
| --- | ---: |
| Animation, 1 layer × 600 frames | 3.60 µs/layer-frame |
| Animation, 10 layers × 600 frames | 3.32 µs/layer-frame |
| Animation, 50 layers × 600 frames | 3.40 µs/layer-frame |
| Animation, 100 layers × 600 frames | 3.42 µs/layer-frame |
| Serialize 100 layers × 100 iterations | 50.31 ms |
| Build image alpha geometry × 25 iterations | 19.69 ms |

These numbers are a local reference, not a cross-machine pass/fail threshold.

## Phase 1 measurement

The new avatar boundary validates and migrates a 100-layer payload 100 times in
585.73 ms on the baseline machine (about 5.86 ms per avatar). The same run
measured JSON serialization at 57.12 ms for 100 iterations; animation and image
geometry remained within baseline variance. The validation ceiling is kept
deliberately broad for slower CI runners while exact artifacts provide the
useful trend line.

## Phase 2 measurement

The extracted blink scheduler and microphone-envelope calculation execute
100,000 combined iterations in 43.37 ms on the baseline machine. The smoke
ceiling is 1,000 ms to catch accidental per-frame algorithmic regressions on
slower CI hardware. The cumulative 100-layer animation result remained at
3.45 µs/layer-frame in the same run.

## Phase 3 measurement

Main-scene decomposition does not add work to the avatar animation hot path.
After extraction, the cumulative gate measured 3.23 µs/layer-frame for 100
layers, 547.71 ms for 100 validations of a 100-layer avatar, 40.05 ms for
100,000 runtime-service updates, 52.56 ms for 100 serialization passes, and
19.04 ms for 25 image-geometry builds. All smoke budgets passed. Controller
contracts add coverage for FFmpeg arguments, capture cleanup, zoom limits,
session recovery selection, and PNG worker encoding.

## Phase 4 measurement

The cumulative gate measured 3.26 µs/layer-frame at 100 layers, 548.41 ms for
100 validations of a 100-layer avatar, 40.86 ms for 100,000 runtime-service
updates, 53.63 ms for 100 serialization passes, and 19.20 ms for 25
image-geometry builds. All smoke budgets passed. Sprite-domain tests cover the
canonical persistent-key inventory, structured value round trips and
ownership, costume migration, alpha geometry, and animated fallback bounds.

## Phase 5 measurement

The cumulative gate measured 3.21 µs/layer-frame at 100 layers, 543.93 ms for
100 validations of a 100-layer avatar, 39.80 ms for 100,000 runtime-service
updates, 53.36 ms for 100 serialization passes, and 19.67 ms for 25
image-geometry builds. All smoke budgets passed. UI component tests add the
shared style, click-through, width clamp, resize edge, and editor-chrome routing
contracts without instantiating the full application scene.

## Phase 6 measurement

The cumulative gate measured 3.37 µs/layer-frame at 100 layers, 581.67 ms for
100 validations of a 100-layer avatar, 41.40 ms for 100,000 runtime-service
updates, 55.25 ms for 100 serialization passes, 20.05 ms for 25 image-geometry
builds, and 396.42 ms for one million import-boundary validation iterations.
All smoke budgets passed. Integration coverage adds valid and malformed APNG,
truncated PSD, exact PackBits row, Stream Deck packet/URL/path, NDI geometry,
and shutdown-ownership contracts.

## Phase 7 measurement

The cumulative gate measured 3.37 µs/layer-frame for active animation at 100
layers and 0.24 µs/layer-frame for the new 100-layer idle fast path. The
representative eye-target badge workload (250 layers × 60 frames) measured
316.09 ms using the removed per-row scan model and 3.67 ms using the registry,
an 86.1× speedup. One million indexed registry/target queries took 611.81 ms.
The same run measured 571.48 ms for avatar validation, 40.45 ms for runtime
services, 54.82 ms for serialization, 19.41 ms for image geometry, and 389.64
ms for import validation; every smoke budget passed. Exact JSON remains in the
ignored `.artifacts/performance.json` and CI artifacts.

## Phase 8 measurement

The cumulative suite contains 504 assertions and passes without failures. A
standalone macOS production pack exported and launched from `.artifacts/`
without source fallbacks or runtime errors. The only warning was the expected
unavailable optional background-hotkey extension in a pack-only smoke.
Release contracts cover every preset's indirect-resource manifest, native
library mappings, product metadata, save extension, documentation, optional
native startup, and obsolete/generated asset removal.

Five text scenes formerly embedded generated font glyph caches: 30,947,981
bytes in total became 80,363 bytes, removing 30,867,618 bytes and over 70,000
generated lines while preserving external font resources. The final local
performance run measured 3.29 µs/layer-frame active and 0.23 idle at 100
layers, 552.88 ms validation, 39.76 ms runtime services, 53.90 ms
serialization, 18.89 ms image geometry, 383.33 ms import validation, 609.40 ms
for one million registry queries, and 3.67 ms for the indexed 250-layer eye
target workload (84.5× versus the former scan model). Every smoke budget passed.

## Patched third-party limitation

godot-ndi v1.2.6 has an open upstream macOS shutdown crash that reproduces
merely by loading the extension, even without creating an NDI node. Isolation
identified the `ViewportTextureRouter` core-level destructor querying an
already-deinitialized `RenderingServer`; active output also left asynchronous
texture callbacks targeting an object deleted too early. PNGTuberPlus now
quiesces the router during scene deinitialization, retains it through rendering
cleanup, and deletes it at core deinitialization without server access. The
rebuilt, ad-hoc-signed universal debug and release libraries pass both
extension-only game shutdown and active `NDIOutput` shutdown on Godot 4.6.3
with NDI Runtime 6.3.1.

The source patch, build inputs, and exact binary digests are maintained in
`addons/godot-ndi/PATCHES.md`. `scripts/run_ndi_teardown_smoke.sh` reproduces
the upstream extension-only scenario and a rendered active-output shutdown on
macOS whenever the NDI runtime is available. Upstream issue 44 remains open, so
upgrades must re-audit and either drop or rebase the local patch.

Follow-up qualification passed 509 assertions, five consecutive idle/active
native teardown runs, the macOS resource-pack export/launch, and all performance
budgets. The cumulative run measured 3.58 µs/layer-frame active and 0.25 idle at
100 layers, 595.96 ms validation, 41.96 ms runtime services, 58.19 ms
serialization, 20.40 ms image geometry, 399.93 ms import validation, 649.67 ms
for one million registry queries, and 3.81 ms for indexed eye-target lookup.

## Phase 9 measurement

> Updated: 2026-08-17 — real application lifecycle coverage

The production-scene runner passes 378 behavioral assertions across startup,
load, unsigned identifiers, hierarchy, migrated idle motion, costumes 1–10,
ancestor visibility, manual hiding, rejected input, and persisted round trips.
The complementary isolated suite passes 652 assertions. On the baseline M1 Max
with Godot 4.6.3, a complete 100-layer load took 221.40 ms and a 250-layer load
took 475.82 ms; exact time and static-memory observations are stored in
`.artifacts/performance-avatar-load.json`. Existing budgets also passed (3.60
microseconds per active 100-layer animation frame, 0.25 idle, 1,219.65 ms for
100 schema validations, and 3.85 ms for the indexed 250-layer eye-target
workload). Five consecutive 120-frame active NDI teardown repetitions passed.

## Phase 10 boundary gate

> Updated: 2026-08-17 — explicit application-state boundaries

The production-scene runner now makes 390 assertions, including the canonical
Area2D-to-layer resolver and selection API before and after a persisted round
trip. The isolated suite makes 686 assertions, including deterministic
selection cycling and source contracts that prevent feature scripts from
assigning held selection, calling private `Global` methods, or duplicating the
three-parent scene traversal. The full Godot 4.6.3 compile, behavioral, and NDI
teardown gates pass after routing production enumeration through the live sprite
registry.

## Phase 11 main-scene gate

> Updated: 2026-08-17 — controller extraction and edit-lifecycle coverage

The real application runner passes 401 assertions after adding duplicate-layer
and replacement mutation coverage through the decomposed controller graph. The
isolated suite passes 710 assertions, including controller compilation, pure
duplicate-name import matching, dependency-injection contracts, stable facade
contracts, and a 650-line ceiling for `main.gd` (currently 597 lines). A verbose
real-scene run reports no leaked `Object` instances after moving the duplicate
sprite's reparent guard before scene insertion.

On the baseline M1 Max with Godot 4.6.3, complete avatar loads measured 223.78
ms for 100 layers and 412.56 ms for 250 layers. The wider performance gate also
passed at 3.49 microseconds per active 100-layer animation frame, 0.25 idle,
608.70 ms for 100 schema validations, and 4.83 ms for the indexed 250-layer
eye-target workload. The 120-frame active NDI teardown smoke and standalone
macOS pack export both pass.

## Phase 12 sprite-runtime gate

> Updated: 2026-08-17 — decomposed layer policies and runtime ownership

The production application runner passes 410 assertions, including real
appendage construction, static-sprite replacement, appendage teardown, and
static-sprite restoration through the extracted wiggle runtime. The isolated
suite passes 740 assertions. It directly covers talk/blink/edit-preview and
costume visibility, cycle-safe hierarchy traversal, wiggle width interpolation,
root orientation, arc projection/tangent, alpha silhouette reach, auto-fit path
and coverage output, plus source contracts for visual/collision/wiggle ownership
different-size replacement/collision synchronization, and the 1,000-line sprite
facade ceiling (`spriteObject.gd` is 951 lines).

The Phase 12 M1 Max run measured 3.48 microseconds per active 100-layer
animation frame and 0.25 idle, 625.57 ms for 100 schema validations, and 4.89
ms for indexed eye-target lookup. Complete loads measured 227.17 ms for 100
layers and 475.51 ms for 250 layers. The new pure ribbon benchmark performs ten
complete centerline/endpoint/coverage auto-fits in 220.28 ms and records its
result under `wiggle_geometry` in `.artifacts/performance.json`. All budgets,
the 120-frame active NDI teardown smoke, and standalone macOS pack export pass.

## Phase 13 UI-componentization gate

> Updated: 2026-08-17 — real component scenes and facade ceilings

The production application runner passes 454 assertions. It instantiates all
five settings-tab bodies, changes the active tab, verifies retired left-sidebar
nodes are absent, checks edit-tree processing on player→edit→player
transitions, and exercises selected/unselected inspector presentation. The
isolated suite passes 794 assertions, including layer-tree ordering,
indentation, filtering, and visibility dispatch; tracking scope, mixed values,
and registry-backed target names; settings dependency injection; and source
ceilings of 700 lines for each sidebar and 150 for settings. The resulting
facades are 695, 697, and 123 lines respectively.

On the baseline M1 Max with Godot 4.6.3, the cumulative performance run measured
3.66 microseconds per active 100-layer animation frame, 637.18 ms for 100 schema
validations, 3.88 ms for indexed eye-target lookup, and 220.58 ms for ten ribbon
auto-fits. Complete avatar loads measured 271.15 ms for 100 layers and 465.60 ms
for 250 layers. All smoke budgets, the 120-frame active NDI teardown test, and
the standalone macOS pack export pass.

## Phase 14 mutation, undo, and input gate

> Updated: 2026-08-17 — one canonical mutation path and one input decoder

Every user mutation now reaches history through `MutationCommands`. All 74
former `save_state()` / `save_state_continuous()` call sites across the
sidebars, physics and blend panels, animation clips, the wiggle path editor, the
layer rows, `Global`, and the avatar/import controllers were migrated, and
`tests/unit/test_release_contract.gd` fails the build if any production file
outside the command layer opens a history transaction. `UndoManager` no longer
names a sidebar, a costume change, or the light gizmo: it emits
`state_restored(scope)` and `AvatarController.on_state_restored()` owns the
consequences.

Four defects the migration surfaced are fixed and covered:

- Animation-clip **rename** captured no history at all, so the edit was silently
  reverted by the next unrelated undo.
- **Undo/redo un-hid every eye-hidden layer**, because restore re-derived
  visibility from `costumeLayers` directly and never consulted `userHidden`.
- **No-op commands left dead history entries** — unlinking an already-unparented
  layer, and arming a visibility-toggle capture that was then cancelled, both
  pushed snapshots before deciding there was nothing to do.
- **Restored sprites reparented on a deferred 0.1s timer**, leaving the
  hierarchy briefly wrong and leaking a `SceneTreeTimer` and an `Image` at exit.
  Restore now links parents synchronously once the whole snapshot exists.

Continuous edits are keyed by gesture rather than one global latch. The old
latch reset only on a mouse release, so keyboard-driven edits merged
indefinitely and a second control touched during the same press captured no
history at all. Gestures are scoped to layer and property, and `end_gesture(name)`
ends only the named gesture so a per-frame poll cannot cut short an unrelated
drag still in flight.

Foreground key commands, background capture, and Stream Deck costume keys share
`autoload/input/input_commands.gd`, a pure decoder holding the guards as data.
Timing-based interactions (origin tap versus hold, ribbon-path escape) stay in
`Global`, where their state belongs.

The production application runner passes 476 assertions, adding discrete,
continuous, structural, and no-op command coverage; undo/redo round trips;
restored-child hierarchy; hand-hidden layers surviving undo; and the history
bound under sustained editing. The isolated suite passes 878 assertions,
including the new `test_mutation_commands` suite that exercises the command
layer against a recording history sink and the decoder against plain
dictionaries — transaction counts, aborted no-ops, nested composites, gesture
scoping, property validation, and every guard on foreground, background, and
device decoding.

On the baseline M1 Max with Godot 4.6.3, the cumulative performance run measured
3.50 microseconds per active 100-layer animation frame, 538.88 ms for 100 schema
validations, 3.72 ms for indexed eye-target lookup, and 217.94 ms for ten ribbon
auto-fits. Complete avatar loads measured 284.70 ms for 100 layers and 536.17 ms
for 250 layers. All smoke budgets, the 120-frame active NDI teardown test, and
the standalone macOS pack export pass, and the production runner now exits with
no leaked ObjectDB instances.

## Phase 15 performance and lifecycle gate

> Updated: 2026-08-17 — seven qualified workloads with ceilings and trend values

`scripts/run_performance.sh` now also runs
`tests/performance/lifecycle_runner.tscn`, which measures seven production-scene
workloads against a 100-layer rig and writes
`.artifacts/performance-lifecycle.json`. Baseline on an M1 Max with Godot 4.6.3:

| Workload | Measurement | Ceiling |
|---|---|---|
| Costume switching | 5.49 ms per switch (200 switches) | 8000 ms total |
| Hierarchy rebuild | 82.21 ms per full rebuild of 100 rows; 4.80 ms per refresh-only pass | 12000 ms total |
| Sidebar refresh | 6.88 ms per frame on the edit page, 6.87 ms on the player page | 6000 ms total |
| Command undo memory | 50 entries at 561 KB each, 28.05 MB total, 2.18 ms per command | 600 MB |
| Wiggle tick | 153.36 us per layer per tick across 25 simulating ribbons | 500 us |
| Cancelled-load teardown | 38.86 ms worker drain, 40.61 ms unwind, 21.00 ms teardown | 8000 ms |
| Repeated shutdown | 5 cycles, 80.73 ms slowest, 1 object of drift | 8000 ms per cycle |

No workload regressed against the Phase 12/13 baselines. Animation improved from
3.66 to 3.36 microseconds per active 100-layer frame, schema validation from
637.18 to 531.45 ms, indexed eye-target lookup from 3.88 to 3.77 ms, and ribbon
auto-fit from 220.58 to 207.41 ms. Complete avatar loads measured 233.62 ms for
100 layers and 371.14 ms for 250 layers, against 271.15 ms and 465.60 ms at
Phase 13. Load timings vary by roughly 15% run to run, so treat the direction as
unchanged rather than as an improvement.

Two measurement bugs were found and fixed while building the gate, both of which
had been silently reporting success:

- Wall-clock frame timing measured the `Engine.max_fps` pacing interval rather
  than the work, so every page and every configuration returned the same number.
  The runner now uncaps the frame rate for its whole run.
- `updateData()` yields a frame and then abandons stale generations, so an
  un-awaited loop of 50 rebuilds coalesced into one and reported 0.04 ms per
  rebuild instead of 82 ms. Both sidebar refresh calls are now awaited.

Two acceptance claims are established structurally rather than by timing,
because per-frame cost at 100 layers is dominated by the layers themselves and
the signal cannot be separated from noise. "Player mode performs no hidden edit
work" is proved by `can_process()` returning false for both sidebars on the
player page and true for both on the edit page. Wiggle cost is measured by
driving `_update_wiggle` directly, after asserting that all 25 ribbons built
their meshes and that the chain advances across frames.

One real defect was surfaced and fixed: tearing the scene down during an avatar
load stranded the load coroutine, which resumed against a dead scene and leaked
a `GDScriptFunctionState` at exit. `avatar_controller.shutdown()` now sets a
cancellation flag, every suspension point in `load_avatar()` re-checks it, and a
cancelled load calls `_abandon_load()` to release its decode buffers and dismiss
its progress dialog. The production runner and the lifecycle gate both exit with
no leaked ObjectDB instances.

The active NDI teardown smoke was run three additional times on macOS and passed
each time. Windows and Linux hosts were not available in this session, so the
cross-platform half of the native lifecycle check remains outstanding for CI.

The production application runner passes 476 assertions and the isolated suite
passes 900, including a new contract that each of the seven workloads keeps both
a measurement and a ceiling, that the performance gate invokes the lifecycle
runner, and that avatar loads carry explicit cancellation.

Hierarchy rebuild at 82 ms for a 100-layer rig is the slowest user-facing
workload measured. It is a first baseline rather than a regression, so it was
recorded and left alone under this phase's rule of optimizing only measured
regressions.

## Phase 16 completion audit

> Updated: 2026-08-17 — dead paths removed, clean-checkout gate green

The audit removed nineteen unreferenced functions, the browser `localStorage`
persistence path (the project has no web export preset), and the
`Global.pushUpdate()` notification facade with its thirteen call sites. It also
extracted the z-index overlay out of the state singleton into
`ui_scenes/zIndex/z_index_editor.gd`, taking `global.gd` from 1042 to 929 lines,
and renamed the menu command surface on `main.gd` out of signal-handler spelling.

One contract was found passing against thirteen violations. The check for the
legacy notification facade matched the literal `"Global.pushUpdate("`, while
every caller reached the singleton through an injected `_global` reference. It
now matches the call rather than one spelling of the receiver. A contract that
pins a spelling instead of a shape is worth re-reading whenever it has never
failed.

### Oversized files and their responsibilities

| File | Lines | Responsibility |
|---|---|---|
| `spriteObject.gd` | 954 | One layer's scene-facing facade over its visual, collision, wiggle, and animation runtimes |
| `global.gd` | 929 | Application state and input routing: selection, modes, microphone, key command dispatch |
| `import_controller.gd` | 714 | The import and replace lifecycle: dialogs, parser threads, worker-pool preparation, review flow |
| `viewer.gd` | 690 | Right sidebar scene facade; wires the layer tree, tracking, details, physics, and blend components |
| `sprite_viewer.gd` | 686 | Left sidebar scene facade; wires selection presentation, normal maps, rotation preview, and animation |
| `main.gd` | 608 | Main scene coordinator over five controllers, plus the public menu command surface |

Each remaining large file is one facade or one lifecycle. None is a grab bag.

### Release matrix

The full gate passes from a **clean checkout** of the branch (a fresh clone into
a temporary directory), which is what proves nothing depends on untracked files
in a working tree: 488 real-scene assertions, 901 isolated assertions,
performance budgets, active NDI teardown, and the standalone pack export.

All three export presets produce a resource pack and each exported pack boots the
full production scene on this host. The platform-native half remains for CI: the
Windows D3D12 and Agility SDK path and the Linux NDI extension cannot be
exercised from a macOS host, so Windows and Linux runtime and native lifecycle
smokes are unverified locally.

### Legacy save shapes

The schema supports exactly two shapes, unversioned (v0) and `_schemaVersion: 1`.
Both are fixture-tested in `tests/unit/test_persistence.gd`
(`avatar_v0.json`, `settings_v0.json`), alongside schema rejections, the bundled
default avatar, unsigned identifier preservation, costume membership round-trip,
and atomic write recovery. The production runner adds a live save/load round trip
across all ten costumes.

### Knowingly retained

Dormant lighting (`_create_light_gizmo()` returns before loading its script, so
`_light_gizmo` is always null and `"_light"` never reaches a save), unreachable
folder replace, the persisted-but-unread `eyeTrackForward`, and the 82 ms
hierarchy rebuild. Each is recorded in `docs/evaluation.md` with the reason.
