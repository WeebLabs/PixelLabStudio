class_name PSDParser

# PSD Layer data class
class PSDLayer:
	var name: String = ""
	var left: int = 0
	var top: int = 0
	var right: int = 0
	var bottom: int = 0
	var width: int = 0
	var height: int = 0
	var opacity: int = 255
	var visible: bool = true
	var channels: Array = []  # Array of {id: int, length: int, data: PackedByteArray}
	var image: Image = null   # Composed RGBA image

# PSD File data class
class PSDFile:
	var width: int = 0
	var height: int = 0
	var layers: Array = []  # Array of PSDLayer
	var error: String = ""

# Internal state
var _file: FileAccess = null
var progress: float = 0.0  # 0.0 to 1.0, safe to read from another thread
var status_text: String = "Starting..."

# Big-endian binary reading helpers
# PSD is big-endian; Godot's get_16/get_32 are little-endian

func _read_u8() -> int:
	return _file.get_8()

func _read_u16() -> int:
	var b0 = _file.get_8()
	var b1 = _file.get_8()
	return (b0 << 8) | b1

func _read_s16() -> int:
	var val = _read_u16()
	if val >= 0x8000:
		val -= 0x10000
	return val

func _read_u32() -> int:
	var b0 = _file.get_8()
	var b1 = _file.get_8()
	var b2 = _file.get_8()
	var b3 = _file.get_8()
	return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

func _read_s32() -> int:
	var val = _read_u32()
	if val >= 0x80000000:
		val -= 0x100000000
	return val

func _read_bytes(count: int) -> PackedByteArray:
	return _file.get_buffer(count)

# PackBits RLE decompression
func _decode_packbits(data: PackedByteArray, expected_size: int) -> PackedByteArray:
	var result = PackedByteArray()
	result.resize(expected_size)
	var pos = 0
	var out_pos = 0

	while pos < data.size() and out_pos < expected_size:
		var n = data[pos]
		pos += 1

		if n < 128:
			# Literal run: copy next n+1 bytes
			var count = n + 1
			for i in range(count):
				if pos < data.size() and out_pos < expected_size:
					result[out_pos] = data[pos]
					pos += 1
					out_pos += 1
		elif n > 128:
			# Repeated run: repeat next byte 257-n times
			var count = 257 - n
			var val = 0
			if pos < data.size():
				val = data[pos]
				pos += 1
			for i in range(count):
				if out_pos < expected_size:
					result[out_pos] = val
					out_pos += 1
		# n == 128: no-op

	return result

# Main parse entry point
func parse(path: String) -> PSDFile:
	var result = PSDFile.new()
	progress = 0.0
	status_text = "Opening file..."

	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		result.error = "Cannot open file: " + path
		return result

	# === HEADER (26 bytes) ===
	var signature = _file.get_buffer(4).get_string_from_ascii()
	if signature != "8BPS":
		result.error = "Not a valid PSD file (bad signature)."
		_file = null
		return result

	var version = _read_u16()
	if version != 1:
		result.error = "PSB (Large Document) format is not supported. Only PSD (version 1) is supported."
		_file = null
		return result

	# Skip 6 reserved bytes
	_file.get_buffer(6)

	var num_channels = _read_u16()
	var height = _read_u32()
	var width = _read_u32()
	var depth = _read_u16()
	var color_mode = _read_u16()

	result.width = width
	result.height = height

	if depth != 8:
		result.error = "Only 8-bit depth is supported. This file uses " + str(depth) + "-bit depth."
		_file = null
		return result

	if color_mode != 3:  # 3 = RGB
		var mode_name = "Unknown"
		match color_mode:
			0: mode_name = "Bitmap"
			1: mode_name = "Grayscale"
			2: mode_name = "Indexed"
			4: mode_name = "CMYK"
			7: mode_name = "Multichannel"
			8: mode_name = "Duotone"
			9: mode_name = "Lab"
		result.error = mode_name + " color mode is not supported. Only RGB is supported."
		_file = null
		return result

	progress = 0.05
	status_text = "Reading header..."

	# === COLOR MODE DATA ===
	var color_data_length = _read_u32()
	if color_data_length > 0:
		_file.get_buffer(color_data_length)

	# === IMAGE RESOURCES ===
	var image_resources_length = _read_u32()
	if image_resources_length > 0:
		_file.get_buffer(image_resources_length)

	# === LAYER AND MASK INFORMATION ===
	var layer_mask_length = _read_u32()
	if layer_mask_length == 0:
		result.error = "PSD file contains no layer data."
		_file = null
		return result

	var layer_mask_end = _file.get_position() + layer_mask_length

	# Layer info
	var layer_info_length = _read_u32()
	if layer_info_length == 0:
		result.error = "PSD file contains no layer info."
		_file = null
		return result

	var layer_info_end = _file.get_position() + layer_info_length

	# Layer count (signed - negative means first alpha channel contains transparency)
	var layer_count = _read_s16()
	layer_count = abs(layer_count)

	if layer_count == 0:
		result.error = "PSD file contains no layers."
		_file = null
		return result

	progress = 0.1
	status_text = "Reading layer records..."

	# === PARSE LAYER RECORDS ===
	var layers: Array = []

	for i in range(layer_count):
		var layer = PSDLayer.new()

		# Bounds
		layer.top = _read_s32()
		layer.left = _read_s32()
		layer.bottom = _read_s32()
		layer.right = _read_s32()
		layer.width = layer.right - layer.left
		layer.height = layer.bottom - layer.top

		# Channel info
		var channel_count = _read_u16()
		layer.channels = []
		for c in range(channel_count):
			var channel_id = _read_s16()
			var channel_data_length = _read_u32()
			layer.channels.append({"id": channel_id, "length": channel_data_length, "data": PackedByteArray()})

		# Blend mode signature
		var blend_sig = _file.get_buffer(4).get_string_from_ascii()
		# Blend mode key
		var blend_key = _file.get_buffer(4).get_string_from_ascii()

		# Opacity
		layer.opacity = _read_u8()

		# Clipping
		var _clipping = _read_u8()

		# Flags
		var flags = _read_u8()
		layer.visible = not (flags & 0x02)  # Bit 1: layer hidden

		# Filler
		var _filler = _read_u8()

		# Extra data
		var extra_data_length = _read_u32()
		var extra_data_end = _file.get_position() + extra_data_length

		if extra_data_length > 0:
			# Layer mask data
			var mask_data_length = _read_u32()
			if mask_data_length > 0:
				_file.get_buffer(mask_data_length)

			# Layer blending ranges
			var blending_length = _read_u32()
			if blending_length > 0:
				_file.get_buffer(blending_length)

			# Layer name (Pascal string, padded to 4-byte boundary)
			var name_length = _read_u8()
			if name_length > 0:
				layer.name = _file.get_buffer(name_length).get_string_from_ascii()
			else:
				layer.name = "Layer " + str(i)

			# Pad to 4-byte boundary (name_length + 1 byte for the length byte itself)
			var padded_name_size = name_length + 1
			while padded_name_size % 4 != 0:
				padded_name_size += 1
				_file.get_8()
		else:
			layer.name = "Layer " + str(i)

		# Skip remaining extra data
		if _file.get_position() < extra_data_end:
			_file.get_buffer(extra_data_end - _file.get_position())

		layers.append(layer)

	# === READ CHANNEL IMAGE DATA ===
	for i in range(layer_count):
		var layer = layers[i]
		progress = 0.2 + 0.5 * (float(i) / max(layer_count, 1))
		status_text = "Reading layer " + str(i + 1) + "/" + str(layer_count) + "..."

		for c in range(layer.channels.size()):
			var channel = layer.channels[c]
			var data_length = channel["length"]

			if data_length < 2:
				# No data for this channel
				if data_length > 0:
					_file.get_buffer(data_length)
				continue

			var compression = _read_u16()
			var remaining = data_length - 2

			if layer.width <= 0 or layer.height <= 0:
				# Zero-size layer (group divider, etc.)
				if remaining > 0:
					_file.get_buffer(remaining)
				continue

			var expected_size = layer.width * layer.height

			if compression == 0:
				# Raw uncompressed
				var raw_data = _file.get_buffer(remaining)
				channel["data"] = raw_data
			elif compression == 1:
				# PackBits RLE
				# First, read per-scanline byte counts (one u16 per row)
				var scanline_counts = PackedByteArray()
				var total_compressed = 0
				for row in range(layer.height):
					var count = _read_u16()
					total_compressed += count

				# Read all compressed data
				var compressed_data = _file.get_buffer(total_compressed)

				# Decompress
				channel["data"] = _decode_packbits(compressed_data, expected_size)
			else:
				# ZIP compression not supported
				result.error = "ZIP compression in layer data is not supported."
				_file = null
				return result

	# === COMPOSE RGBA IMAGES ===
	var compose_idx = 0
	for layer in layers:
		progress = 0.7 + 0.3 * (float(compose_idx) / max(layers.size(), 1))
		status_text = "Composing layer " + str(compose_idx + 1) + "/" + str(layers.size()) + "..."
		compose_idx += 1
		if layer.width <= 0 or layer.height <= 0:
			continue

		var pixel_count = layer.width * layer.height
		var rgba = PackedByteArray()
		rgba.resize(pixel_count * 4)

		# Initialize to transparent black
		rgba.fill(0)

		# Map channel data by ID
		var channel_map = {}
		for ch in layer.channels:
			channel_map[ch["id"]] = ch["data"]

		# Channel IDs: 0=Red, 1=Green, 2=Blue, -1=Alpha
		var r_data = channel_map.get(0, PackedByteArray())
		var g_data = channel_map.get(1, PackedByteArray())
		var b_data = channel_map.get(2, PackedByteArray())
		var a_data = channel_map.get(-1, PackedByteArray())

		var has_r = r_data.size() >= pixel_count
		var has_g = g_data.size() >= pixel_count
		var has_b = b_data.size() >= pixel_count
		var has_a = a_data.size() >= pixel_count

		for p in range(pixel_count):
			var idx = p * 4
			rgba[idx] = r_data[p] if has_r else 0
			rgba[idx + 1] = g_data[p] if has_g else 0
			rgba[idx + 2] = b_data[p] if has_b else 0

			var alpha = a_data[p] if has_a else 255
			# Apply layer opacity
			alpha = int(alpha * layer.opacity / 255.0)
			rgba[idx + 3] = alpha

		layer.image = Image.create_from_data(layer.width, layer.height, false, Image.FORMAT_RGBA8, rgba)

		# Clear raw channel data to free memory
		for ch in layer.channels:
			ch["data"] = PackedByteArray()

	progress = 1.0
	status_text = "Done!"
	result.layers = layers
	_file = null
	return result
