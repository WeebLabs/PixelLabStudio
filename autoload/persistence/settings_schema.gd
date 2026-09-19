class_name SettingsSchema
extends RefCounted

const ValueCodec = preload("res://autoload/persistence/value_codec.gd")

const CURRENT_VERSION := 3
const COSTUME_SLOT_COUNT := 10

# The viewer's two microphone meters, and the settings their thumbs store.
# Since schema 3, "micThresholdDb" is the level in dBFS that opens the voice gate
# (the Level meter runs from MIC_LEVEL_MIN_DB to MIC_LEVEL_MAX_DB), and
# "micDurationThreshold" is the Duration thumb, from 0 to MIC_DURATION_FULL_MS.
# The Duration bar fills when the gate opens and drains 1 ms per ms after, so the
# mouth stays open MIC_DURATION_FULL_MS - thumb ms once the voice drops.
#
# Schemas 1 and 2 stored "volume", a linear threshold on the loudest spectrum
# bin (full scale 0.2), and "sense", the point a 0-1 value decaying at e^-2t had
# to fall below, which is a hold of ln(1 / sense) / 2 seconds. Both are converted
# once on load. The level conversion is approximate: the old reading was one FFT
# bin, the new one is the RMS of the voice band, which reads a few dB higher on
# speech, so a converted threshold opens slightly more readily.
const MIC_LEVEL_MIN_DB := -60.0
const MIC_LEVEL_MAX_DB := 0.0
const MIC_DURATION_FULL_MS := 1000.0
const LEGACY_MIC_LEVEL_RANGE := 0.2
const LEGACY_MIC_DURATION_RANGE := 1.0


static func defaults() -> Dictionary:
	return {
		"_schemaVersion": CURRENT_VERSION,
		"newUser": true,
		"lastAvatar": "",
		"micThresholdDb": -40.0,
		"micDurationThreshold": 850.0,
		"windowSize": var_to_str(Vector2i(1280, 720)),
		"useStreamDeck": false,
		"audioDevice": "",
		"bounce": 250.0,
		"gravity": 1000.0,
		"maxFPS": 60,
		"backgroundColor": var_to_str(Color.TRANSPARENT),
		"filtering": true,
		"costumeKeys": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
		"blinkSpeed": 1.0,
		"blinkChance": 200,
		"bounceOnCostumeChange": false,
		"ndiEnabled": false,
		"ndiWidth": 512,
		"ndiMode": "auto",
		"ndiManualWidth": 800,
		"ndiManualHeight": 1200,
		"ndiCropRect": [-500.0, -800.0, 500.0, 200.0],
		"ndiSourceName": "PixelLab Studio",
		"recordingFormat": "webm",
		"recordingFPS": 30,
		"leftSidebarWidth": 265.0,
		"rightSidebarWidth": 310.0,
		"leftSidebarTab": 0,
		"rightSidebarTab": 0,
		"wigglePresets": {},
	}


static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("Settings must be a JSON object.")

	var source: Dictionary = value
	# Preserve unknown JSON-safe keys so a newer build can round-trip through an
	# older one without losing extension preferences.
	var result: Dictionary = source.duplicate(true)
	var base := defaults()
	# Read before it is stamped: the microphone thumbs need to know which meaning
	# the stored values carry.
	var source_version := ValueCodec.int_value(source.get("_schemaVersion"), 0, 0, 1 << 30)
	result["_schemaVersion"] = CURRENT_VERSION
	result["newUser"] = ValueCodec.bool_value(source.get("newUser"), base["newUser"])
	result["lastAvatar"] = ValueCodec.string_value(source.get("lastAvatar"), base["lastAvatar"], 32768)
	_normalize_microphone(source, result, base, source_version)

	var window_size := ValueCodec.vector2i_value(source.get("windowSize"), Vector2i(1280, 720))
	window_size.x = clampi(window_size.x, 640, 16384)
	window_size.y = clampi(window_size.y, 360, 16384)
	result["windowSize"] = var_to_str(window_size)

	result["useStreamDeck"] = ValueCodec.bool_value(source.get("useStreamDeck"), base["useStreamDeck"])
	result["audioDevice"] = ValueCodec.string_value(source.get("audioDevice"), base["audioDevice"], 1024)
	result["bounce"] = ValueCodec.float_value(source.get("bounce"), base["bounce"], 0.0, 10000.0)
	result["gravity"] = ValueCodec.float_value(source.get("gravity"), base["gravity"], 0.0, 50000.0)
	result["maxFPS"] = ValueCodec.int_value(source.get("maxFPS"), base["maxFPS"], 0, 1000)
	result["backgroundColor"] = var_to_str(ValueCodec.color_value(source.get("backgroundColor"), Color.TRANSPARENT))
	result["filtering"] = ValueCodec.bool_value(source.get("filtering"), base["filtering"])
	result["costumeKeys"] = _costume_keys(source.get("costumeKeys"), base["costumeKeys"])
	result["blinkSpeed"] = ValueCodec.float_value(source.get("blinkSpeed"), base["blinkSpeed"], 0.0, 60.0)
	result["blinkChance"] = ValueCodec.int_value(source.get("blinkChance"), base["blinkChance"], 1, 1000000)
	result["bounceOnCostumeChange"] = ValueCodec.bool_value(source.get("bounceOnCostumeChange"), base["bounceOnCostumeChange"])

	result["ndiEnabled"] = ValueCodec.bool_value(source.get("ndiEnabled"), base["ndiEnabled"])
	result["ndiWidth"] = ValueCodec.int_value(source.get("ndiWidth"), base["ndiWidth"], 64, 8192)
	var ndi_mode := ValueCodec.string_value(source.get("ndiMode"), base["ndiMode"], 16)
	result["ndiMode"] = ndi_mode if ndi_mode in ["auto", "manual"] else base["ndiMode"]
	result["ndiManualWidth"] = ValueCodec.int_value(source.get("ndiManualWidth"), base["ndiManualWidth"], 64, 8192)
	result["ndiManualHeight"] = ValueCodec.int_value(source.get("ndiManualHeight"), base["ndiManualHeight"], 64, 8192)
	if not source.has("ndiCropRect") and source.has("ndiRulerY"):
		var legacy_bottom := ValueCodec.float_value(source["ndiRulerY"], 200.0, -100000.0, 100000.0)
		result["ndiCropRect"] = [-500.0, legacy_bottom - 1000.0, 500.0, legacy_bottom]
	else:
		result["ndiCropRect"] = _crop_rect(source.get("ndiCropRect"), base["ndiCropRect"])
	result["ndiSourceName"] = ValueCodec.string_value(source.get("ndiSourceName"), base["ndiSourceName"], 128).strip_edges()
	if result["ndiSourceName"].is_empty():
		result["ndiSourceName"] = base["ndiSourceName"]

	var recording_format := ValueCodec.string_value(source.get("recordingFormat"), base["recordingFormat"], 16).to_lower()
	result["recordingFormat"] = recording_format if recording_format in ["webm", "gif", "apng"] else base["recordingFormat"]
	var recording_fps := ValueCodec.int_value(source.get("recordingFPS"), base["recordingFPS"], 1, 240)
	result["recordingFPS"] = recording_fps
	result["leftSidebarWidth"] = ValueCodec.float_value(source.get("leftSidebarWidth"), base["leftSidebarWidth"], 160.0, 1200.0)
	result["rightSidebarWidth"] = ValueCodec.float_value(source.get("rightSidebarWidth"), base["rightSidebarWidth"], 160.0, 1200.0)
	result["leftSidebarTab"] = ValueCodec.int_value(source.get("leftSidebarTab"), base["leftSidebarTab"], 0, 1)
	result["rightSidebarTab"] = ValueCodec.int_value(source.get("rightSidebarTab"), base["rightSidebarTab"], 0, 2)
	result["wigglePresets"] = source["wigglePresets"].duplicate(true) if source.get("wigglePresets") is Dictionary else {}

	return {"ok": true, "value": result, "error": ""}


static func _normalize_microphone(source: Dictionary, result: Dictionary, base: Dictionary, source_version: int) -> void:
	if source_version >= 3 or source.has("micThresholdDb") or source.has("micDurationThreshold"):
		result["micThresholdDb"] = ValueCodec.float_value(
			source.get("micThresholdDb"), base["micThresholdDb"], MIC_LEVEL_MIN_DB, MIC_LEVEL_MAX_DB
		)
		result["micDurationThreshold"] = ValueCodec.float_value(
			source.get("micDurationThreshold"), base["micDurationThreshold"], 0.0, MIC_DURATION_FULL_MS
		)
	else:
		# A value the user set is converted. One that was never stored takes
		# today's default rather than a conversion of the old one.
		result["micThresholdDb"] = base["micThresholdDb"]
		result["micDurationThreshold"] = base["micDurationThreshold"]
		if source.has("volume"):
			var level := _mic_thumb(source.get("volume"), 0.015, LEGACY_MIC_LEVEL_RANGE, source_version)
			result["micThresholdDb"] = legacy_level_to_db(level)
		if source.has("sense"):
			var sense := _mic_thumb(source.get("sense"), 0.75, LEGACY_MIC_DURATION_RANGE, source_version)
			result["micDurationThreshold"] = MIC_DURATION_FULL_MS - legacy_sense_to_hold_ms(sense)
	# One source of truth: the converted keys replace the old ones.
	result.erase("volume")
	result.erase("sense")


static func legacy_level_to_db(level: float) -> float:
	if level <= 0.0:
		return MIC_LEVEL_MIN_DB
	return clampf(20.0 * log(level) / log(10.0), MIC_LEVEL_MIN_DB, MIC_LEVEL_MAX_DB)


# The old decay fell as e^-2t from 1 and the mouth closed once it dropped below
# `sense`, which takes ln(1 / sense) / 2 seconds. A sense of 1 or more never let
# the mouth open past the trigger frame, a hold of 0 now; 0 held it forever,
# clamped to the longest hold the Duration bar can express.
static func legacy_sense_to_hold_ms(sense: float) -> float:
	if sense >= 1.0:
		return 0.0
	if sense <= 0.0:
		return MIC_DURATION_FULL_MS
	return clampf(1000.0 * log(1.0 / sense) / 2.0, 0.0, MIC_DURATION_FULL_MS)


# A legacy microphone meter's thumb position, clamped to that meter's scale.
# Schema 1 and earlier stored the mirror (the slider read as a sensitivity knob),
# so those values are flipped once. Clamping happens first: an out-of-range v1
# value meant a threshold pinned at one end, and it has to land on that same end.
static func _mic_thumb(value: Variant, fallback: float, range_max: float, source_version: int) -> float:
	var mirrored := source_version < 2
	# The fallback is expressed in the current meaning, so a missing or unusable
	# value on an old source has to enter the flip already mirrored to come back
	# out as today's default.
	var source_fallback := (range_max - fallback) if mirrored else fallback
	var thumb := ValueCodec.float_value(value, source_fallback, 0.0, range_max)
	return (range_max - thumb) if mirrored else thumb


static func _costume_keys(value: Variant, fallback: Array) -> Array:
	var source: Array = value if value is Array else []
	var result: Array[String] = []
	for index in range(COSTUME_SLOT_COUNT):
		var default_key: String = fallback[index]
		var key := ValueCodec.string_value(source[index] if index < source.size() else default_key, default_key, 64)
		result.append(key)
	return result


static func _crop_rect(value: Variant, fallback: Array) -> Array:
	if not value is Array or value.size() != 4:
		return fallback.duplicate()
	var result := [
		ValueCodec.float_value(value[0], fallback[0], -100000.0, 100000.0),
		ValueCodec.float_value(value[1], fallback[1], -100000.0, 100000.0),
		ValueCodec.float_value(value[2], fallback[2], -100000.0, 100000.0),
		ValueCodec.float_value(value[3], fallback[3], -100000.0, 100000.0),
	]
	if result[2] - result[0] < 1.0 or result[3] - result[1] < 1.0:
		return fallback.duplicate()
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
