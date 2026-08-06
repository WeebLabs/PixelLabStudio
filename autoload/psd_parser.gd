class_name PSDParser

const ImportBudget = preload("res://autoload/import/import_limits.gd")

var _use_native := ClassDB.class_exists("PSDNative")

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
var _file_size: int = 0
var _cancelled := false
var progress: float = 0.0  # 0.0 to 1.0, safe to read from another thread
var status_text: String = "Starting..."

func cancel() -> void:
	_cancelled = true

func _has_bytes(count: int, boundary: int = -1) -> bool:
	if _file == null:
		return false
	var limit := _file_size if boundary < 0 else mini(boundary, _file_size)
	return ImportBudget.section_fits(_file.get_position(), count, limit)

func _failure(result: PSDFile, message: String) -> PSDFile:
	result.error = message
	status_text = message
	_file = null
	return result

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
	var data_size = data.size()

	while pos < data_size and out_pos < expected_size and not _cancelled:
		var n = data[pos]
		pos += 1

		if n < 128:
			# Literal run: copy next n+1 bytes
			var count = mini(n + 1, mini(data_size - pos, expected_size - out_pos))
			for i in range(count):
				result[out_pos] = data[pos]
				pos += 1
				out_pos += 1
		elif n > 128:
			# Repeated run: repeat next byte 257-n times
			if pos >= data_size:
				break
			var val = data[pos]
			pos += 1
			var count = mini(257 - n, expected_size - out_pos)
			for i in range(count):
				result[out_pos] = val
				out_pos += 1
		# n == 128: no-op

	return result

func _packbits_rows_valid(scanline_bytes: PackedByteArray, data: PackedByteArray, width: int, height: int) -> bool:
	var data_offset := 0
	for row in range(height):
		if _cancelled:
			return false
		var table_offset := row * 2
		var row_size := (scanline_bytes[table_offset] << 8) | scanline_bytes[table_offset + 1]
		if not ImportBudget.section_fits(data_offset, row_size, data.size()):
			return false
		var input_offset := data_offset
		var row_end := data_offset + row_size
		var output_size := 0
		while input_offset < row_end:
			var control := data[input_offset]
			input_offset += 1
			if control < 128:
				var literal_count := control + 1
				if input_offset + literal_count > row_end:
					return false
				input_offset += literal_count
				output_size += literal_count
			elif control > 128:
				if input_offset >= row_end:
					return false
				input_offset += 1
				output_size += 257 - control
			if output_size > width:
				return false
		if output_size != width:
			return false
		data_offset = row_end
	return data_offset == data.size()

# Main parse entry point
func parse(path: String) -> PSDFile:
	var result = PSDFile.new()
	_cancelled = false
	progress = 0.0
	status_text = "Opening file..."

	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		result.error = "Cannot open file: " + path
		return result
	_file_size = _file.get_length()
	if _file_size < 26 or _file_size > ImportBudget.MAX_FILE_BYTES:
		return _failure(result, "PSD file size is outside the supported range.")

	# === HEADER (26 bytes) ===
	var signature = _file.get_buffer(4).get_string_from_ascii()
	if signature != "8BPS":
		return _failure(result, "Not a valid PSD file (bad signature).")

	var version = _read_u16()
	if version != 1:
		return _failure(result, "PSB (Large Document) format is not supported. Only PSD (version 1) is supported.")

	# Skip 6 reserved bytes
	_file.get_buffer(6)

	var num_channels = _read_u16()
	var height = _read_u32()
	var width = _read_u32()
	var depth = _read_u16()
	var color_mode = _read_u16()

	result.width = width
	result.height = height
	if not ImportBudget.count_valid(num_channels, ImportBudget.MAX_CHANNELS):
		return _failure(result, "PSD channel count exceeds the import resource budget.")
	if not ImportBudget.dimensions_valid(width, height):
		return _failure(result, "PSD dimensions exceed the import resource budget.")

	if depth != 8:
		return _failure(result, "Only 8-bit depth is supported. This file uses " + str(depth) + "-bit depth.")

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
		return _failure(result, mode_name + " color mode is not supported. Only RGB is supported.")

	progress = 0.05
	status_text = "Reading header..."

	# === COLOR MODE DATA ===
	if not _has_bytes(4):
		return _failure(result, "PSD color-mode section is truncated.")
	var color_data_length = _read_u32()
	if color_data_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(color_data_length):
		return _failure(result, "PSD color-mode section is invalid or too large.")
	_file.seek(_file.get_position() + color_data_length)

	# === IMAGE RESOURCES ===
	if not _has_bytes(4):
		return _failure(result, "PSD image-resource section is truncated.")
	var image_resources_length = _read_u32()
	if image_resources_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(image_resources_length):
		return _failure(result, "PSD image-resource section is invalid or too large.")
	_file.seek(_file.get_position() + image_resources_length)

	# === LAYER AND MASK INFORMATION ===
	if not _has_bytes(4):
		return _failure(result, "PSD layer-and-mask section is truncated.")
	var layer_mask_length = _read_u32()
	if layer_mask_length == 0:
		return _failure(result, "PSD file contains no layer data.")
	if layer_mask_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(layer_mask_length):
		return _failure(result, "PSD layer-and-mask section is invalid or too large.")

	var layer_mask_end = _file.get_position() + layer_mask_length

	# Layer info
	if not _has_bytes(4, layer_mask_end):
		return _failure(result, "PSD layer-info section is truncated.")
	var layer_info_length = _read_u32()
	if layer_info_length == 0:
		return _failure(result, "PSD file contains no layer info.")
	if layer_info_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(layer_info_length, layer_mask_end):
		return _failure(result, "PSD layer-info section is invalid or too large.")

	var layer_info_end = _file.get_position() + layer_info_length

	# Layer count (signed - negative means first alpha channel contains transparency)
	if not _has_bytes(2, layer_info_end):
		return _failure(result, "PSD layer count is truncated.")
	var layer_count = _read_s16()
	layer_count = abs(layer_count)

	if not ImportBudget.count_valid(layer_count, ImportBudget.MAX_LAYERS):
		return _failure(result, "PSD layer count is empty or exceeds the import resource budget.")

	progress = 0.1
	status_text = "Reading layer records..."

	# === PARSE LAYER RECORDS ===
	var layers: Array = []
	var decoded_working_bytes := 0

	for i in range(layer_count):
		if _cancelled:
			return _failure(result, "Import cancelled.")
		if not _has_bytes(18, layer_info_end):
			return _failure(result, "PSD layer record %d is truncated." % i)
		var layer = PSDLayer.new()

		# Bounds
		layer.top = _read_s32()
		layer.left = _read_s32()
		layer.bottom = _read_s32()
		layer.right = _read_s32()
		layer.width = layer.right - layer.left
		layer.height = layer.bottom - layer.top
		if layer.width > 0 and layer.height > 0 and not ImportBudget.dimensions_valid(layer.width, layer.height):
			return _failure(result, "PSD layer %d dimensions exceed the import resource budget." % i)

		# Channel info
		var channel_count = _read_u16()
		if channel_count > ImportBudget.MAX_CHANNELS:
			return _failure(result, "PSD layer %d has too many channels." % i)
		if layer.width > 0 and layer.height > 0:
			decoded_working_bytes += layer.width * layer.height * (4 + mini(channel_count, 4))
			if decoded_working_bytes > ImportBudget.MAX_DECODED_BYTES:
				return _failure(result, "PSD layers exceed the decoded-memory resource budget.")
		if not _has_bytes(channel_count * 6 + 16, layer_info_end):
			return _failure(result, "PSD layer %d channel table is truncated." % i)
		layer.channels = []
		for c in range(channel_count):
			var channel_id = _read_s16()
			var channel_data_length = _read_u32()
			layer.channels.append({"id": channel_id, "length": channel_data_length, "data": PackedByteArray()})

		# Blend mode signature
		var blend_sig = _file.get_buffer(4).get_string_from_ascii()
		if blend_sig != "8BIM":
			return _failure(result, "PSD layer %d has an invalid blend signature." % i)
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
		if extra_data_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(extra_data_length, layer_info_end):
			return _failure(result, "PSD layer %d extra-data section is invalid." % i)
		var extra_data_end = _file.get_position() + extra_data_length

		if extra_data_length > 0:
			# Layer mask data
			if not _has_bytes(4, extra_data_end):
				return _failure(result, "PSD layer %d mask metadata is truncated." % i)
			var mask_data_length = _read_u32()
			if not _has_bytes(mask_data_length, extra_data_end):
				return _failure(result, "PSD layer %d mask data is truncated." % i)
			_file.seek(_file.get_position() + mask_data_length)

			# Layer blending ranges
			if not _has_bytes(4, extra_data_end):
				return _failure(result, "PSD layer %d blending metadata is truncated." % i)
			var blending_length = _read_u32()
			if not _has_bytes(blending_length, extra_data_end):
				return _failure(result, "PSD layer %d blending data is truncated." % i)
			_file.seek(_file.get_position() + blending_length)

			# Layer name (Pascal string, padded to 4-byte boundary)
			if not _has_bytes(1, extra_data_end):
				return _failure(result, "PSD layer %d name is truncated." % i)
			var name_length = _read_u8()
			if not _has_bytes(name_length, extra_data_end):
				return _failure(result, "PSD layer %d name is truncated." % i)
			if name_length > 0:
				layer.name = _file.get_buffer(name_length).get_string_from_ascii()
			else:
				layer.name = "Layer " + str(i)

			# Pad to 4-byte boundary (name_length + 1 byte for the length byte itself)
			var padded_name_size = name_length + 1
			while padded_name_size % 4 != 0:
				padded_name_size += 1
				if not _has_bytes(1, extra_data_end):
					return _failure(result, "PSD layer %d name padding is truncated." % i)
				_file.get_8()
		else:
			layer.name = "Layer " + str(i)

		# Skip remaining extra data
		if _file.get_position() < extra_data_end:
			_file.seek(extra_data_end)

		layers.append(layer)

	# === READ CHANNEL IMAGE DATA ===
	for i in range(layer_count):
		if _cancelled:
			return _failure(result, "Import cancelled.")
		var layer = layers[i]
		progress = 0.2 + 0.5 * (float(i) / max(layer_count, 1))
		status_text = "Reading layer " + str(i + 1) + "/" + str(layer_count) + "..."

		for c in range(layer.channels.size()):
			var channel = layer.channels[c]
			var data_length: int = channel["length"]
			if data_length > ImportBudget.MAX_CHUNK_BYTES or not _has_bytes(data_length, layer_info_end):
				return _failure(result, "PSD layer %d channel %d data is invalid or truncated." % [i, c])
			var channel_end: int = _file.get_position() + data_length

			if data_length < 2:
				# No data for this channel
				if data_length > 0:
					_file.seek(channel_end)
				continue

			var compression = _read_u16()
			var remaining = data_length - 2

			if layer.width <= 0 or layer.height <= 0:
				# Zero-size layer (group divider, etc.)
				if remaining > 0:
					_file.seek(channel_end)
				continue

			var expected_size = layer.width * layer.height

			if compression == 0:
				# Raw uncompressed
				if remaining < expected_size:
					return _failure(result, "PSD layer %d raw channel is shorter than its pixel data." % i)
				var raw_data = _file.get_buffer(remaining)
				channel["data"] = raw_data
			elif compression == 1:
				# PackBits RLE
				# Bulk-read all per-scanline byte counts (2 bytes each, big-endian)
				var scanline_table_size: int = layer.height * 2
				if scanline_table_size > remaining:
					return _failure(result, "PSD layer %d RLE scanline table is truncated." % i)
				var scanline_bytes = _file.get_buffer(scanline_table_size)
				var total_compressed = 0
				for row in range(layer.height):
					var off = row * 2
					total_compressed += (scanline_bytes[off] << 8) | scanline_bytes[off + 1]
				if total_compressed > remaining - scanline_table_size:
					return _failure(result, "PSD layer %d RLE data is truncated." % i)

				# Read all compressed data
				var compressed_data = _file.get_buffer(total_compressed)
				if not _packbits_rows_valid(scanline_bytes, compressed_data, layer.width, layer.height):
					return _failure(result, "PSD layer %d contains invalid PackBits rows." % i)

				# Decompress
				if _use_native:
					channel["data"] = ClassDB.class_call_static(
						"PSDNative", "decode_packbits", compressed_data, expected_size
					)
				else:
					channel["data"] = _decode_packbits(compressed_data, expected_size)
			else:
				# ZIP compression not supported
				return _failure(result, "ZIP compression in layer data is not supported.")
			if _cancelled:
				return _failure(result, "Import cancelled.")
			if _file.get_position() < channel_end:
				_file.seek(channel_end)

	# === COMPOSE RGBA IMAGES ===
	var compose_idx = 0
	for layer in layers:
		if _cancelled:
			return _failure(result, "Import cancelled.")
		progress = 0.7 + 0.3 * (float(compose_idx) / max(layers.size(), 1))
		status_text = "Composing layer " + str(compose_idx + 1) + "/" + str(layers.size()) + "..."
		compose_idx += 1
		if layer.width <= 0 or layer.height <= 0:
			continue

		var pixel_count = layer.width * layer.height
		var rgba: PackedByteArray

		# Map channel data by ID
		var channel_map = {}
		for ch in layer.channels:
			channel_map[ch["id"]] = ch["data"]

		# Channel IDs: 0=Red, 1=Green, 2=Blue, -1=Alpha
		var r_data = channel_map.get(0, PackedByteArray())
		var g_data = channel_map.get(1, PackedByteArray())
		var b_data = channel_map.get(2, PackedByteArray())
		var a_data = channel_map.get(-1, PackedByteArray())

		if _use_native:
			rgba = ClassDB.class_call_static(
				"PSDNative", "compose_rgba", r_data, g_data, b_data, a_data, pixel_count, layer.opacity
			)
		else:
			rgba = PackedByteArray()
			rgba.resize(pixel_count * 4)

			var has_r = r_data.size() >= pixel_count
			var has_g = g_data.size() >= pixel_count
			var has_b = b_data.size() >= pixel_count
			var has_a = a_data.size() >= pixel_count

			# Branch outside the hot loop to eliminate per-pixel conditionals
			if has_r and has_g and has_b and has_a:
				if layer.opacity == 255:
					# Fast path: all channels, full opacity — no math per pixel
					for p in range(pixel_count):
						var idx = p * 4
						rgba[idx] = r_data[p]
						rgba[idx + 1] = g_data[p]
						rgba[idx + 2] = b_data[p]
						rgba[idx + 3] = a_data[p]
				else:
					# All channels, partial opacity
					var opa = layer.opacity / 255.0
					for p in range(pixel_count):
						var idx = p * 4
						rgba[idx] = r_data[p]
						rgba[idx + 1] = g_data[p]
						rgba[idx + 2] = b_data[p]
						rgba[idx + 3] = int(a_data[p] * opa)
			elif has_r and has_g and has_b:
				# RGB but no alpha — fully opaque at layer opacity
				var opa = layer.opacity
				for p in range(pixel_count):
					var idx = p * 4
					rgba[idx] = r_data[p]
					rgba[idx + 1] = g_data[p]
					rgba[idx + 2] = b_data[p]
					rgba[idx + 3] = opa
			else:
				# Rare: missing channels — general fallback
				var opa = layer.opacity / 255.0
				for p in range(pixel_count):
					var idx = p * 4
					rgba[idx] = r_data[p] if has_r else 0
					rgba[idx + 1] = g_data[p] if has_g else 0
					rgba[idx + 2] = b_data[p] if has_b else 0
					var alpha = a_data[p] if has_a else 255
					rgba[idx + 3] = int(alpha * opa)

		layer.image = Image.create_from_data(layer.width, layer.height, false, Image.FORMAT_RGBA8, rgba)

		# Clear raw channel data to free memory
		for ch in layer.channels:
			ch["data"] = PackedByteArray()

	progress = 1.0
	status_text = "Done!"
	result.layers = layers
	_file = null
	return result
