class_name BlendMode
extends RefCounted

# Per-layer blend mode registry + render-tier categorization.
#
# Three render tiers, so only the modes that truly need it pay any cost:
#   NORMAL           -> CanvasItemMaterial, PREMULT_ALPHA. The default; no shader, no backbuffer.
#   ADD / SUBTRACT   -> CanvasItemMaterial native hardware blend. Correct under premultiplied
#                       alpha, still no backbuffer.
#   everything else  -> ShaderMaterial (blend_modes.gdshader) + a BackBufferCopy that snapshots
#                       the layers below so the shader can read the backdrop.
#
# The persisted value is the enum int. ORDER IS STABLE — only ever append new modes,
# never reorder, or old saves will remap to the wrong mode.

enum Mode {
	NORMAL = 0,
	DARKEN = 1,
	MULTIPLY = 2,
	COLOR_BURN = 3,
	LIGHTEN = 4,
	SCREEN = 5,
	COLOR_DODGE = 6,
	ADD = 7,          # a.k.a. Linear Dodge
	OVERLAY = 8,
	SOFT_LIGHT = 9,
	HARD_LIGHT = 10,
	DIFFERENCE = 11,
	EXCLUSION = 12,
	SUBTRACT = 13,
}

# Dropdown labels, index-aligned with the enum value so OptionButton item id == Mode int.
const DISPLAY := [
	"Normal",        # 0
	"Darken",        # 1
	"Multiply",      # 2
	"Color Burn",    # 3
	"Lighten",       # 4
	"Screen",        # 5
	"Color Dodge",   # 6
	"Add",           # 7
	"Overlay",       # 8
	"Soft Light",    # 9
	"Hard Light",    # 10
	"Difference",    # 11
	"Exclusion",     # 12
	"Subtract",      # 13
]

const SHADER := preload("res://effects/blend/blend_modes.gdshader")

# Native tier: composites straight over the layers below via the hardware blend stage,
# so it needs no screen read.
static func is_native(mode: int) -> bool:
	return mode == Mode.NORMAL or mode == Mode.ADD or mode == Mode.SUBTRACT

# Non-native modes must read the backdrop from the screen backbuffer.
static func needs_backbuffer(mode: int) -> bool:
	return not is_native(mode)

# CanvasItemMaterial.BlendMode for a native-tier mode (premultiplied = Normal).
static func native_blend(mode: int) -> int:
	match mode:
		Mode.ADD: return CanvasItemMaterial.BLEND_MODE_ADD
		Mode.SUBTRACT: return CanvasItemMaterial.BLEND_MODE_SUB
		_: return CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

static func display_name(mode: int) -> String:
	return DISPLAY[mode] if mode >= 0 and mode < DISPLAY.size() else DISPLAY[0]

static func count() -> int:
	return DISPLAY.size()
