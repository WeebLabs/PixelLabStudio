# PNGTuberPlus patches

The bundled extension is based on upstream `godot-ndi` v1.2.6 at commit
`d99e749aff1aa09daf9a7beadfb699d56ccd106b`.

## macOS RenderingServer teardown

`patches/0001-fix-render-router-teardown.patch` explicitly quiesces the
`ViewportTextureRouter` at scene deinitialization, while `RenderingServer` is
still valid. The router remains alive through server cleanup so asynchronous
texture callbacks retain a valid target, then it is deleted at core
deinitialization without querying the rendering server. This fixes both the
extension-only `std::system_error: mutex lock failed: Invalid argument` abort
and the active-output callback use-after-free.

The macOS debug and release libraries are rebuilt from the patched source
against `godot-cpp` commit
`58d1de720b8ffe9f8ffcdfe3a85148582cfd2e74` (Godot 4.6 stable), using:

```bash
git apply --unidiff-zero patches/0001-fix-render-router-teardown.patch
scons target=template_debug platform=macos arch=universal precision=single lto=auto use_static_cpp=yes debug_symbols=no optimize=speed
scons target=template_release platform=macos arch=universal precision=single lto=auto use_static_cpp=yes debug_symbols=no optimize=speed
codesign --force --sign - project/addons/godot-ndi/bin/macos/libgodot-ndi.macos.template_debug.universal.dylib
codesign --force --sign - project/addons/godot-ndi/bin/macos/libgodot-ndi.macos.template_release.universal.dylib
```

Both libraries contain `x86_64` and `arm64` slices. Their SHA-256 digests are:

- debug: `7bed10a7eecc2c07b3815d4db2f7c27581d6a5481683961373179f2deff1538a`
- release: `4fc04977156eacdf7b048b5aaf87a1a0095f5ff04458f1a7313d80bf74663f42`

The original defect is tracked by upstream issue 44. The regression smoke uses
both an idle headless game and a rendered active-output game; fresh headless
editor projects can independently hit a Godot 4.6.3 extension-documentation
crash during shutdown. Re-audit the patch when upgrading to an upstream release
that resolves issue 44.
