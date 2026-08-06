# Quality Baseline

> Updated: 2026-08-06 — Phase 8 release qualification gates

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
scripts, then runs isolated unit and contract tests in a minimal project. This
separation prevents user settings, microphones, Stream Deck devices, and native
output integrations from affecting deterministic tests or requiring optional
native runtimes on CI. When a macOS NDI runtime is installed, the same gate also
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

`run_performance.sh` benchmarks eight repeatable CPU paths: animation
evaluation at 1/10/50/100 layers, 100-layer avatar JSON serialization,
100-layer schema validation/migration, runtime blink/microphone state updates,
alpha-to-polygon image geometry, one million binary import-boundary checks,
one million indexed sprite lookups, and indexed-versus-quadratic eye-target
resolution. It stores exact results and enforces broad smoke ceilings of 15 microseconds per
100-layer animation layer-frame, 500 ms for serialization, 3,000 ms for schema
validation, 1,000 ms per 100,000 runtime-service updates, and 200 ms for image
geometry, 2,000 ms each for one million import and sprite-registry validations,
and 100 ms for 15,000 indexed eye-target lookups. Phase work should compare
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
