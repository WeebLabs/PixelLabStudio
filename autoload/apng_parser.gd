class_name APNGParser

const ImportBudget = preload("res://autoload/import/import_limits.gd")

class APNGFrame:
	var image: Image = null
	var delay_ms: int = 100

class APNGResult:
	var width: int = 0
	var height: int = 0
	var frames: Array = []
	var error: String = ""

var progress: float = 0.0
var status_text: String = "Starting..."
var _cancelled := false
var _crc_table: Array = []

const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10]
const PASSTHROUGH_CHUNKS = ["PLTE", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT"]

func cancel() -> void:
	_cancelled = true

static func _u32(data: PackedByteArray, offset: int = 0) -> int:
	return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]

static func _signature_valid(data: PackedByteArray) -> bool:
	if data.size() != PNG_SIGNATURE.size():
		return false
	for i in range(PNG_SIGNATURE.size()):
		if data[i] != PNG_SIGNATURE[i]:
			return false
	return true

static func is_apng(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var file_size := file.get_length()
	if file_size < 20 or file_size > ImportBudget.MAX_FILE_BYTES:
		return false
	if not _signature_valid(file.get_buffer(8)):
		return false

	var scan_end := mini(file_size, 8192)
	while file.get_position() < scan_end:
		if not ImportBudget.section_fits(file.get_position(), 12, file_size):
			return false
		var length_bytes := file.get_buffer(4)
		var chunk_length := _u32(length_bytes)
		if chunk_length > ImportBudget.MAX_CHUNK_BYTES:
			return false
		var type_bytes := file.get_buffer(4)
		if not ImportBudget.section_fits(file.get_position(), chunk_length + 4, file_size):
			return false
		var chunk_type := type_bytes.get_string_from_ascii()
		if chunk_type == "acTL":
			return chunk_length == 8
		file.seek(file.get_position() + chunk_length + 4)
		if chunk_type == "IDAT" or chunk_type == "IEND":
			break
	return false

func _init_crc_table() -> void:
	if not _crc_table.is_empty():
		return
	_crc_table.resize(256)
	for n in range(256):
		var c: int = n
		for _bit in range(8):
			c = 0xEDB88320 ^ (c >> 1) if c & 1 else c >> 1
		_crc_table[n] = c

func _compute_crc(data: PackedByteArray) -> int:
	var crc: int = 0xFFFFFFFF
	for byte in data:
		crc = _crc_table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

func _make_chunk(chunk_type: String, data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	var length := data.size()
	result.append((length >> 24) & 0xFF)
	result.append((length >> 16) & 0xFF)
	result.append((length >> 8) & 0xFF)
	result.append(length & 0xFF)
	var type_bytes := chunk_type.to_ascii_buffer()
	result.append_array(type_bytes)
	result.append_array(data)
	var crc_input := type_bytes.duplicate()
	crc_input.append_array(data)
	var crc := _compute_crc(crc_input)
	result.append((crc >> 24) & 0xFF)
	result.append((crc >> 16) & 0xFF)
	result.append((crc >> 8) & 0xFF)
	result.append(crc & 0xFF)
	return result

func _build_png_buffer(width: int, height: int, bit_depth: int, color_type: int, idat_data: PackedByteArray, aux_chunks: Array) -> PackedByteArray:
	var png := PackedByteArray(PNG_SIGNATURE)
	var ihdr := PackedByteArray()
	for shift in [24, 16, 8, 0]:
		ihdr.append((width >> shift) & 0xFF)
	for shift in [24, 16, 8, 0]:
		ihdr.append((height >> shift) & 0xFF)
	ihdr.append_array(PackedByteArray([bit_depth, color_type, 0, 0, 0]))
	png.append_array(_make_chunk("IHDR", ihdr))
	for chunk in aux_chunks:
		png.append_array(_make_chunk(chunk["type"], chunk["data"]))
	png.append_array(_make_chunk("IDAT", idat_data))
	png.append_array(_make_chunk("IEND", PackedByteArray()))
	return png

func _failure(result: APNGResult, message: String) -> APNGResult:
	result.error = message
	status_text = message
	return result

func parse(path: String) -> APNGResult:
	var result := APNGResult.new()
	_cancelled = false
	progress = 0.0
	status_text = "Opening APNG..."
	_init_crc_table()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(result, "Failed to open file: " + path)
	var file_size := file.get_length()
	if file_size < 20 or file_size > ImportBudget.MAX_FILE_BYTES:
		return _failure(result, "APNG file size is outside the supported range.")
	if not _signature_valid(file.get_buffer(8)):
		return _failure(result, "Not a valid PNG file.")

	var bit_depth := 8
	var color_type := 6
	var declared_frames := 0
	var saw_ihdr := false
	var saw_actl := false
	var saw_iend := false
	var seen_idat := false
	var first_frame_is_default := false
	var collecting_default_idat := false
	var aux_chunks: Array = []
	var fctl_list: Array = []
	var frame_data_list: Array = []
	var current_fctl: Dictionary = {}
	var current_idat_data := PackedByteArray()
	var accumulated_frame_bytes := 0
	status_text = "Parsing APNG chunks..."

	while file.get_position() < file_size:
		if _cancelled:
			return _failure(result, "Import cancelled.")
		if not ImportBudget.section_fits(file.get_position(), 12, file_size):
			return _failure(result, "Truncated PNG chunk header.")
		var chunk_length := _u32(file.get_buffer(4))
		if chunk_length > ImportBudget.MAX_CHUNK_BYTES:
			return _failure(result, "PNG chunk exceeds the import resource budget.")
		var type_bytes := file.get_buffer(4)
		var chunk_type := type_bytes.get_string_from_ascii()
		if not ImportBudget.section_fits(file.get_position(), chunk_length + 4, file_size):
			return _failure(result, "Truncated PNG chunk: " + chunk_type)
		var chunk_data := file.get_buffer(chunk_length)
		var stored_crc := _u32(file.get_buffer(4))
		var crc_input := type_bytes.duplicate()
		crc_input.append_array(chunk_data)
		if _compute_crc(crc_input) != stored_crc:
			return _failure(result, "PNG checksum failed for chunk " + chunk_type + ".")

		match chunk_type:
			"IHDR":
				if saw_ihdr or chunk_data.size() != 13:
					return _failure(result, "Invalid PNG header.")
				result.width = _u32(chunk_data, 0)
				result.height = _u32(chunk_data, 4)
				if not ImportBudget.dimensions_valid(result.width, result.height):
					return _failure(result, "APNG dimensions exceed the import resource budget.")
				bit_depth = chunk_data[8]
				color_type = chunk_data[9]
				if chunk_data[10] != 0 or chunk_data[11] != 0 or chunk_data[12] > 1:
					return _failure(result, "Unsupported PNG encoding methods.")
				saw_ihdr = true
			"acTL":
				if not saw_ihdr or saw_actl or seen_idat or chunk_data.size() != 8:
					return _failure(result, "Invalid APNG animation header.")
				declared_frames = _u32(chunk_data)
				if not ImportBudget.decoded_images_fit(result.width, result.height, declared_frames):
					return _failure(result, "APNG frame count exceeds the import resource budget.")
				saw_actl = true
			"PLTE", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT":
				if accumulated_frame_bytes + chunk_data.size() > ImportBudget.MAX_CHUNK_BYTES:
					return _failure(result, "PNG metadata exceeds the import resource budget.")
				aux_chunks.append({"type": chunk_type, "data": chunk_data})
				accumulated_frame_bytes += chunk_data.size()
			"fcTL":
				if not saw_actl or chunk_data.size() != 26:
					return _failure(result, "Invalid APNG frame control chunk.")
				if not current_fctl.is_empty():
					fctl_list.append(current_fctl)
					frame_data_list.append(current_idat_data)
					current_idat_data = PackedByteArray()
				current_fctl = _parse_fctl(chunk_data)
				if not _frame_control_valid(current_fctl, result.width, result.height):
					return _failure(result, "APNG frame bounds or operations are invalid.")
				if not seen_idat:
					first_frame_is_default = true
					collecting_default_idat = true
			"IDAT":
				seen_idat = true
				if collecting_default_idat or (first_frame_is_default and not current_fctl.is_empty()):
					if not _append_frame_data(current_idat_data, chunk_data, accumulated_frame_bytes):
						return _failure(result, "Compressed APNG data exceeds the import resource budget.")
					current_idat_data.append_array(chunk_data)
					accumulated_frame_bytes += chunk_data.size()
			"fdAT":
				if current_fctl.is_empty() or chunk_data.size() <= 4:
					return _failure(result, "Invalid APNG frame data chunk.")
				var frame_bytes := chunk_data.slice(4)
				if not _append_frame_data(current_idat_data, frame_bytes, accumulated_frame_bytes):
					return _failure(result, "Compressed APNG data exceeds the import resource budget.")
				current_idat_data.append_array(frame_bytes)
				accumulated_frame_bytes += frame_bytes.size()
				collecting_default_idat = false
			"IEND":
				if chunk_length != 0:
					return _failure(result, "Invalid PNG end chunk.")
				if not current_fctl.is_empty():
					fctl_list.append(current_fctl)
					frame_data_list.append(current_idat_data)
				saw_iend = true
				break
		progress = clampf(float(file.get_position()) / float(file_size) * 0.5, 0.0, 0.5)

	if not saw_iend or not saw_actl or fctl_list.is_empty():
		return _failure(result, "No complete animation was found in the APNG.")
	if fctl_list.size() != declared_frames or frame_data_list.size() != declared_frames:
		return _failure(result, "APNG frame count does not match its animation header.")

	status_text = "Decoding APNG frames..."
	var canvas := Image.create(result.width, result.height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	for i in range(fctl_list.size()):
		if _cancelled:
			return _failure(result, "Import cancelled.")
		var fctl: Dictionary = fctl_list[i]
		var idat_data: PackedByteArray = frame_data_list[i]
		if idat_data.is_empty():
			return _failure(result, "APNG frame %d contains no image data." % i)
		var frame_width: int = fctl["width"]
		var frame_height: int = fctl["height"]
		var offset_x: int = fctl["x_offset"]
		var offset_y: int = fctl["y_offset"]
		var previous_canvas: Image = null
		if fctl["dispose_op"] == 2:
			previous_canvas = canvas.duplicate()

		var frame_image := Image.new()
		var error := frame_image.load_png_from_buffer(_build_png_buffer(
			frame_width, frame_height, bit_depth, color_type, idat_data, aux_chunks
		))
		if error != OK:
			return _failure(result, "Failed to decode APNG frame %d (error %d)." % [i, error])
		if frame_image.get_format() != Image.FORMAT_RGBA8:
			frame_image.convert(Image.FORMAT_RGBA8)

		if fctl["blend_op"] == 0:
			canvas.blit_rect(frame_image, Rect2i(Vector2i.ZERO, frame_image.get_size()), Vector2i(offset_x, offset_y))
		else:
			canvas.blend_rect(frame_image, Rect2i(Vector2i.ZERO, frame_image.get_size()), Vector2i(offset_x, offset_y))

		var frame := APNGFrame.new()
		frame.image = canvas.duplicate()
		var delay_denominator: int = fctl["delay_den"]
		if delay_denominator == 0:
			delay_denominator = 100
		frame.delay_ms = maxi(1, roundi(float(fctl["delay_num"]) * 1000.0 / delay_denominator))
		result.frames.append(frame)

		match fctl["dispose_op"]:
			1:
				canvas.fill_rect(Rect2i(offset_x, offset_y, frame_width, frame_height), Color.TRANSPARENT)
			2:
				canvas = previous_canvas
		progress = 0.5 + 0.5 * float(i + 1) / fctl_list.size()
		status_text = "Decoded frame %d of %d..." % [i + 1, fctl_list.size()]

	progress = 1.0
	status_text = "Done!"
	return result

func _append_frame_data(current: PackedByteArray, incoming: PackedByteArray, total: int) -> bool:
	return incoming.size() <= ImportBudget.MAX_CHUNK_BYTES - current.size() \
		and incoming.size() <= ImportBudget.MAX_FILE_BYTES - total

func _frame_control_valid(frame: Dictionary, canvas_width: int, canvas_height: int) -> bool:
	var width: int = frame["width"]
	var height: int = frame["height"]
	var x: int = frame["x_offset"]
	var y: int = frame["y_offset"]
	return ImportBudget.dimensions_valid(width, height) \
		and x <= canvas_width - width and y <= canvas_height - height \
		and frame["dispose_op"] in [0, 1, 2] and frame["blend_op"] in [0, 1]

func _parse_fctl(data: PackedByteArray) -> Dictionary:
	return {
		"width": _u32(data, 4),
		"height": _u32(data, 8),
		"x_offset": _u32(data, 12),
		"y_offset": _u32(data, 16),
		"delay_num": (data[20] << 8) | data[21],
		"delay_den": (data[22] << 8) | data[23],
		"dispose_op": data[24],
		"blend_op": data[25],
	}
