# Quality Baseline

> Updated: 2026-08-06 — Phase 0 Godot 4.6 baseline

This document records the reproducible safety rails used throughout the
refactor. Exact timing artifacts are written to `.artifacts/` and retained by
CI; they are intentionally not committed.

## Supported toolchain

| Component | Baseline |
| --- | --- |
| Godot | 4.6.3 stable (`7d41c59c4`) |
| Renderer | GL Compatibility |
| `godot-cpp` | `58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74` (4.6-stable API sync) |
| godot-ndi | v1.2.6 release archive, SHA-256 `0ffaf8255a268e9408c344187143b612d37ee5147c1c752b426d6a6b95a4ffe7` |

CI downloads official Godot builds for Linux, macOS, and Windows and verifies
their SHA-256 digests before executing any project code. The PSD extension's
macOS binary is rebuilt against the pinned `godot-cpp` revision. Build
intermediates are ignored and are no longer versioned.

## Quality gates

Run the same checks locally with:

```bash
GODOT_BIN=/absolute/path/to/godot ./scripts/run_tests.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_performance.sh
```

`run_tests.sh` performs a Godot 4.6 recovery-mode import to compile production
scripts, then runs isolated unit and contract tests in a minimal project. This
separation prevents user settings, microphones, Stream Deck devices, and native
output integrations from affecting deterministic tests. Recovery mode is also
required because Godot 4.6.3's normal headless editor shutdown can crash while
generating extension documentation whenever a GDExtension is loaded; that
engine/editor defect is separate from application runtime behavior.

`run_performance.sh` benchmarks five repeatable CPU paths: animation
evaluation at 1/10/50/100 layers, 100-layer avatar JSON serialization,
100-layer schema validation/migration, runtime blink/microphone state updates,
and alpha-to-polygon image geometry. It
stores exact results and enforces broad smoke ceilings of 15 microseconds per
100-layer animation layer-frame, 500 ms for serialization, 3,000 ms for schema
validation, 1,000 ms per 100,000 runtime-service updates, and 200 ms for image
geometry. Phase work should compare
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

## Known third-party limitation

godot-ndi v1.2.6 has an upstream macOS shutdown crash that reproduces merely by
loading the extension, even without creating an NDI node. It is tracked as
upstream issue 44. Production NDI behavior remains available, while automated
imports use Godot recovery mode so the unrelated extension teardown defect
cannot make script tests nondeterministic. The integration phase must re-audit
the upstream issue or replace/isolate the dependency before the final release
gate.
