# Avatar Save Format

> Updated: 2026-08-06 — schema version 1 compatibility contract

User avatars are UTF-8 JSON documents with the `.save` extension. The file is
self-contained: each sprite's diffuse image and optional normal map are stored
as base64-encoded PNG data. Internal settings and crash recovery use
`user://settings.pngtp` and `user://session.pngtp`; those internal filenames do
not change the user-facing avatar extension.

## Root object

The JSON root is an object. Sprite entries use arbitrary non-underscore keys
and must have `type: "sprite"`. Underscore-prefixed keys are reserved for
avatar-level metadata.

| Metadata | Meaning |
| --- | --- |
| `_schemaVersion` | Current value is `1`. Missing means legacy version `0` and is migrated on load. |
| `_eyeTrackingGloballyEnabled` | Avatar-wide eye-tracking switch. |
| `_ndiCropRect` | `[left, top, right, bottom]` in origin-relative pixels. |
| `_ndiRulerY` | Legacy NDI framing compatibility value; current saves mirror the crop bottom. |
| `_light` | Dormant light-gizmo compatibility data (`pos`, `energy`, `color`, `range`, `enabled`). |

Unknown underscore-prefixed metadata is preserved so optional/newer
integrations can round-trip through this build. A schema newer than the current
version is rejected instead of being silently downgraded.

## Sprite entries

Every sprite requires an image `path` and a unique integer-compatible
`identification`. `parentId` is null or another sprite ID. The canonical field
inventory and runtime-property mapping live in
`autoload/domain/sprite_state.gd`; normalization and range limits live in
`autoload/persistence/avatar_save_schema.gd`.

Field groups are:

- Identity/hierarchy: `type`, `path`, `identification`, `parentId`, `pos`,
  `offset`, `zindex`.
- Reactive motion: `drag`, `xFrq`, `xAmp`, `yFrq`, `yAmp`, `rotDrag`,
  `rLimitMin`, `rLimitMax`, `stretchAmount`, `ignoreBounce`, `staticElement`.
- Frames/visibility: `frames`, `animSpeed`, `showTalk`, `showBlink`, `toggle`,
  `costumeLayers`, `clipped`.
- Eye tracking: `eyeTrack`, `eyeTrackDistance`, `eyeTrackSpeed`,
  `eyeTrackInvert`, `eyeTrackMode`, `eyeTrackTargetId`, `eyeTrackType`, and the
  retained compatibility field `eyeTrackForward`.
- Wiggle/animation: the `wiggle*` fields and `animClips`.
- Appearance/output: `blendMode`, `opacity`, `ndiRefLayer`, `normalPath`.
- Embedded art: `imageData` and optional `normalImageData`, both base64 PNG.

Godot types that JSON cannot represent directly are encoded as strings using
`var_to_str`: `pos`, `offset`, `costumeLayers`, `wigglePath`,
`wigglePathWidths`, `animClips`, and light vector/color values. Only
`autoload/persistence/value_codec.gd` may decode legacy Variant strings at a
persistence boundary. Do not call `str_to_var` directly on untrusted input.

## Validation and migration

Loading validates before the live scene is changed:

- maximum JSON file size: 512 MiB;
- maximum sprite count: 10,000;
- maximum base64 characters per embedded image: 384 Mi;
- supported type, required path/ID, unique IDs, property types and ranges;
- hierarchy cycles are rejected; missing parents are normalized to the root;
- invalid/future schema versions are rejected with an actionable error.

Legacy unversioned saves are normalized to schema 1 and receive compatibility
defaults. Costume arrays normalize to ten entries. A legacy `_ndiRulerY` is
retained and can seed the current crop representation.

## Writes and recovery

Images encode off the main thread. JSON writes use a same-directory `.tmp`
file, protect the previous complete destination as `.bak` where replacement is
not atomic, and restore/read that backup when the primary is missing or
invalid. `lastAvatar` changes only after a successful manual save.

Session recovery uses the same avatar schema at `user://session.pngtp`. Settings
use a separate schema, a 4 MiB read limit, and canonical typed defaults.

## Versioning rule

Additive fields with safe defaults may remain within schema 1, but they must be
added to both `SpriteState` and `AvatarSaveSchema` with migration/round-trip
tests. Increment `_schemaVersion` when meaning or representation changes and
add an explicit migration from every supported older version. Never emit a new
representation until the current build can read both old and new fixtures.
