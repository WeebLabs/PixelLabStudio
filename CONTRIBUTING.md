# Contributing to PixelLab Studio

PixelLab Studio targets Godot 4.6. The CI-pinned development release is Godot
4.6.3; use that patch version before diagnosing a project regression.

## Set up the repository

Clone with submodules so the PSD extension receives the pinned `godot-cpp`
revision:

```bash
git clone --recurse-submodules <repository-url>
cd PNGTuberPlus
```

Open `main_scenes/main.tscn` in Godot. Do not commit `.godot/`, generated native
objects, export output, local avatar files, or IDE state.

## Run the acceptance gates

Set `GODOT_BIN` to an absolute path to a Godot 4.6 executable:

```bash
GODOT_BIN=/absolute/path/to/godot ./scripts/run_tests.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_performance.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_export_smoke.sh
GODOT_BIN=/absolute/path/to/godot ./scripts/run_release_checks.sh
```

`run_tests.sh` compiles the production project in recovery mode, runs the
deterministic test project, and performs the native NDI teardown smoke on a
macOS host where the NDI runtime is installed. `run_performance.sh` writes
ignored JSON under `.artifacts/` and enforces broad regression budgets. `run_export_smoke.sh`
creates a production resource pack and launches it from outside the source
tree, catching omitted release dependencies. The combined release command runs
all three gates.

CI runs tests and the resource-pack smoke on Linux, macOS, and Windows. It runs
the repeatable performance gate on Linux. A platform-specific native change
still requires a real exported-build check on that platform.

## Change contracts

- Keep `docs/architecture_guide.md` current for structural changes. Make a
  targeted edit and add a dated `Updated` note; do not rewrite unrelated
  history.
- Add or update tests with behavior changes. Prefer pure services and source
  contracts over instantiating the full application scene.
- Keep user-facing `.save` files compatible. Persistent sprite fields belong in
  `autoload/domain/sprite_state.gd` and
  `autoload/persistence/avatar_save_schema.gd`; update both and add migration
  coverage. See `docs/save_format.md`.
- Treat PSD/APNG/avatar input as untrusted. Validate lengths, counts, decoded
  memory, and hierarchy before mutating the live scene.
- A programmatically created decorative `ColorRect` must use
  `MOUSE_FILTER_IGNORE`. Canvas selection must use a direct physics point query.
- Preserve the existing mixed naming style in touched code; do not bundle a
  repository-wide naming rewrite with a functional change.

## Native and release changes

Read `docs/dependencies.md` before replacing binaries. Never update a native
library without recording its version or source revision, license, supported
platform/architecture matrix, and rebuild or verification steps. Every path in
a `.gdextension` manifest must exist, and debug/release mappings must not claim
unsupported binaries.

Export presets intentionally select the main scene and explicitly include
resources loaded indirectly. When adding `load()`/`preload()` targets that are
not scene dependencies, extend every preset's `include_filter` and the release
contract tests. Release outputs stay below `.artifacts/exports/`.

## Pull requests

Keep commits scoped and explain any compatibility, performance, or native
integration risk. Include the tests run and before/after performance numbers
when a hot path changes. Do not commit personal saves or imported artwork.
