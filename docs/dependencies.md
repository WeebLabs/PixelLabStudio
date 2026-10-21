# Dependency Inventory

> Updated: 2026-08-06 — Godot 4.6 release inventory and native provenance audit

This file records runtime/build dependencies that cannot be understood from a
GDScript call site alone. Version or binary changes must update this inventory,
the relevant manifest, and release tests together.

| Dependency | Pin / source | License | Shipped platforms | Notes |
| --- | --- | --- | --- | --- |
| Godot | 4.6.3 stable (`7d41c59c4`); official archives and SHA-256 values are pinned in CI | MIT | Linux x86_64, macOS universal, Windows x86_64 | Project feature baseline is `4.6`; CI uses the exact patch release. |
| `godot-cpp` | submodule `58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74` | MIT | Build-time | API bindings used to rebuild `psd-native`. |
| `psd-native` | first-party source under `addons/psd-native/src/` | Project/Unlicense | Native binaries are declared by `psd_native.gdextension` | Optional PSD channel decode accelerator; the GDScript parser remains the validation boundary. |
| `godot-ndi` | upstream v1.2.6 (`d99e749aff1aa09daf9a7beadfb699d56ccd106b`); release archive SHA-256 `0ffaf8255a268e9408c344187143b612d37ee5147c1c752b426d6a6b95a4ffe7`; local patch in `addons/godot-ndi/patches/` | MPL-2.0 | Linux x86_64/arm64, macOS universal, Windows x86_64; debug and release | Optional. End users also need the NDI Runtime. macOS binaries are rebuilt against the pinned Godot 4.6 bindings with the issue 44 teardown fix. |
| Background input extension | `bin/gdexample.gdextension`; compiled binaries only | Project/Unlicense | Linux x86_64, macOS, Windows x86_64; debug and release | Supplies `BackgroundInputCapture`. Source is not present, so provenance/rebuildability is a known maintenance risk. The app degrades to foreground-only hotkeys when absent. |
| Godot Stream Deck addon | v1.0-era Boyne Games addon | MIT (bundled `LICENSE.md`) | GDScript; platform bridge path depends on the Stream Deck host | Disabled unless configured. Protocol packets and project paths are validated before use. |
| FFmpeg | external executable discovered at runtime | FFmpeg distribution-dependent | Optional recording backend | Not bundled. WebM recording reports an actionable error when unavailable; APNG/GIF paths do not require it. |
| DirectX Agility SDK | `D3D12Core.dll`, SDK >= project setting (currently 618) | Microsoft SDK terms | Windows export only | Required for D3D12 transparent-window output. Godot exports it from the matching export-template directory when present. |

## Native loading policy

Native features are optional at application startup. Code checks `ClassDB`
before instantiation and must keep a usable non-native path. The exception is a
binary that Godot loads solely because its `.gdextension` manifest is present;
that library must match Godot 4.6 and every declared file must exist.

The production test import uses recovery mode so CI does not require every
optional native runtime. Deterministic tests run in a minimal project without
native extensions. On macOS systems with the NDI runtime,
`scripts/run_ndi_teardown_smoke.sh` loads the patched extension in a clean
project and requires clean idle and active-output game shutdown. The release smoke exports a
production pack and launches it away from the source tree, verifying
script/resource completeness without borrowing local files.

## Upgrade checklist

1. Verify the upstream tag/commit and license from its canonical repository.
2. Record an archive checksum or immutable source revision.
3. Rebuild against the pinned Godot 4.6 `godot-cpp` API when applicable.
4. Inspect every binary's platform and architecture, then keep only matching
   `.gdextension` entries.
5. Run unit, performance, and export smoke gates. Launch a full export on each
   affected native platform.
6. Re-audit known upstream issues before release.

The original NDI teardown defect remains tracked upstream at
https://github.com/unvermuthet/godot-ndi/issues/44. PNGTuberPlus carries the
audited fix until an upstream release supersedes it; see
`addons/godot-ndi/PATCHES.md`.
