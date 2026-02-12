class_name APNGParser

class APNGFrame:
	var image: Image = null
	var delay_ms: int = 100

class APNGResult:
	var width: int = 0
	var height: int = 0
	var frames: Array = []  # Array of APNGFrame
	var error: String = ""

# Thread-safe progress
var progress: float = 0.0
var status_text: String = "Starting..."

# CRC32 lookup table — must be plain Array (not PackedInt32Array) because
# CRC values exceed INT32_MAX and PackedInt32Array truncates to signed 32-bit
var _crc_table: Array = []

# PNG signature
const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10]

static func is_apng(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	# Check PNG signature
	var sig = file.get_buffer(8)
	if sig.size() < 8:
		return false
	for i in range(8):
		if sig[i] != PNG_SIGNATURE[i]:
			return false

	# Scan chunks for acTL (animation control) within first ~8KB
	var bytes_read = 8
	var max_scan = 8192
	while bytes_read < max_scan and file.get_position() < file.get_length():
		var length_bytes = file.get_buffer(4)
		if length_bytes.size() < 4:
			break
		var chunk_length = (length_bytes[0] << 24) | (length_bytes[1] << 16) | (length_bytes[2] << 8) | length_bytes[3]

		var type_bytes = file.get_buffer(4)
		if type_bytes.size() < 4:
			break
		var chunk_type = type_bytes.get_string_from_ascii()

		if chunk_type == "acTL":
			return true

		# Skip data + CRC
		file.seek(file.get_position() + chunk_length + 4)
		bytes_read += 12 + chunk_length

		if chunk_type == "IDAT":
			break  # acTL must appear before IDAT

	return false

func _init_crc_table():
	if _crc_table.size() > 0:
		return
	_crc_table.resize(256)
	for n in range(256):
		var c: int = n
		for _k in range(8):
			if c & 1:
				c = 0xEDB88320 ^ (c >> 1)
			else:
				c = c >> 1
		_crc_table[n] = c

func _compute_crc(data: PackedByteArray) -> int:
	var crc: int = 0xFFFFFFFF
	for i in range(data.size()):
		var idx = (crc ^ data[i]) & 0xFF
		crc = _crc_table[idx] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

func _make_chunk(chunk_type: String, data: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray()

	# Length (4 bytes, big-endian)
	var length = data.size()
	result.append((length >> 24) & 0xFF)
	result.append((length >> 16) & 0xFF)
	result.append((length >> 8) & 0xFF)
	result.append(length & 0xFF)

	# Type (4 bytes)
	var type_bytes = chunk_type.to_ascii_buffer()
	result.append_array(type_bytes)

	# Data
	result.append_array(data)

	# CRC over type + data
	var crc_input = PackedByteArray()
	crc_input.append_array(type_bytes)
	crc_input.append_array(data)
	var crc = _compute_crc(crc_input)
	result.append((crc >> 24) & 0xFF)
	result.append((crc >> 16) & 0xFF)
	result.append((crc >> 8) & 0xFF)
	result.append(crc & 0xFF)

	return result

func _build_png_buffer(width: int, height: int, bit_depth: int, color_type: int, idat_data: PackedByteArray, aux_chunks: Array) -> PackedByteArray:
	var png = PackedByteArray()

	# PNG Signature
	for b in PNG_SIGNATURE:
		png.append(b)

	# IHDR chunk
	var ihdr_data = PackedByteArray()
	ihdr_data.append((width >> 24) & 0xFF)
	ihdr_data.append((width >> 16) & 0xFF)
	ihdr_data.append((width >> 8) & 0xFF)
	ihdr_data.append(width & 0xFF)
	ihdr_data.append((height >> 24) & 0xFF)
	ihdr_data.append((height >> 16) & 0xFF)
	ihdr_data.append((height >> 8) & 0xFF)
	ihdr_data.append(height & 0xFF)
	ihdr_data.append(bit_depth)
	ihdr_data.append(color_type)
	ihdr_data.append(0)  # compression method
	ihdr_data.append(0)  # filter method
	ihdr_data.append(0)  # interlace method
	png.append_array(_make_chunk("IHDR", ihdr_data))

	# Auxiliary chunks (PLTE, tRNS, etc.) needed for correct decoding
	for chunk in aux_chunks:
		png.append_array(_make_chunk(chunk["type"], chunk["data"]))

	# IDAT chunk(s)
	png.append_array(_make_chunk("IDAT", idat_data))

	# IEND chunk
	png.append_array(_make_chunk("IEND", PackedByteArray()))

	return png

func parse(path: String) -> APNGResult:
	var result = APNGResult.new()

	_init_crc_table()

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error = "Failed to open file: " + path
		return result

	status_text = "Reading APNG header..."
	progress = 0.0

	var file_size = file.get_length()

	# Verify PNG signature
	var sig = file.get_buffer(8)
	if sig.size() < 8:
		result.error = "File too small"
		return result
	for i in range(8):
		if sig[i] != PNG_SIGNATURE[i]:
			result.error = "Not a valid PNG file"
			return result

	# Parse all chunks
	var ihdr_data = PackedByteArray()
	var bit_depth: int = 8
	var color_type: int = 6  # RGBA

	var num_frames: int = 0
	var _num_plays: int = 0

	# Auxiliary chunks to pass through to reconstructed PNGs (PLTE, tRNS, etc.)
	var aux_chunks: Array = []

	# Frame control info
	var fctl_list: Array = []  # Array of dictionaries with fcTL data
	var frame_data_list: Array = []  # Array of PackedByteArray (IDAT/fdAT data per frame)

	# Track whether first frame uses default image
	var first_frame_is_default: bool = false
	var seen_idat: bool = false
	var current_fctl: Dictionary = {}
	var current_idat_data: PackedByteArray = PackedByteArray()
	var collecting_default_idat: bool = false

	status_text = "Parsing chunks..."

	while file.get_position() < file_size:
		var length_bytes = file.get_buffer(4)
		if length_bytes.size() < 4:
			break
		var chunk_length = (length_bytes[0] << 24) | (length_bytes[1] << 16) | (length_bytes[2] << 8) | length_bytes[3]

		var type_bytes = file.get_buffer(4)
		if type_bytes.size() < 4:
			break
		var chunk_type = type_bytes.get_string_from_ascii()

		var chunk_data = PackedByteArray()
		if chunk_length > 0:
			chunk_data = file.get_buffer(chunk_length)
		var _crc = file.get_buffer(4)  # skip CRC

		match chunk_type:
			"IHDR":
				ihdr_data = chunk_data
				result.width = (chunk_data[0] << 24) | (chunk_data[1] << 16) | (chunk_data[2] << 8) | chunk_data[3]
				result.height = (chunk_data[4] << 24) | (chunk_data[5] << 16) | (chunk_data[6] << 8) | chunk_data[7]
				bit_depth = chunk_data[8]
				color_type = chunk_data[9]

			"acTL":
				num_frames = (chunk_data[0] << 24) | (chunk_data[1] << 16) | (chunk_data[2] << 8) | chunk_data[3]
				_num_plays = (chunk_data[4] << 24) | (chunk_data[5] << 16) | (chunk_data[6] << 8) | chunk_data[7]

			"PLTE", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT":
				# Preserve chunks needed for correct color decoding
				aux_chunks.append({"type": chunk_type, "data": chunk_data})

			"fcTL":
				# If we were collecting data for a previous frame, save it
				if current_fctl.size() > 0:
					fctl_list.append(current_fctl)
					frame_data_list.append(current_idat_data)
					current_idat_data = PackedByteArray()

				current_fctl = _parse_fctl(chunk_data)

				if !seen_idat:
					first_frame_is_default = true
					collecting_default_idat = true

			"IDAT":
				seen_idat = true
				if collecting_default_idat or (first_frame_is_default and current_fctl.size() > 0):
					current_idat_data.append_array(chunk_data)

			"fdAT":
				# Strip 4-byte sequence number, keep the rest as IDAT data
				if chunk_data.size() > 4:
					current_idat_data.append_array(chunk_data.slice(4))
				collecting_default_idat = false

			"IEND":
				# Save last frame
				if current_fctl.size() > 0:
					fctl_list.append(current_fctl)
					frame_data_list.append(current_idat_data)
				break

		progress = clampf(float(file.get_position()) / float(file_size), 0.0, 0.5)

	if fctl_list.is_empty():
		result.error = "No animation frames found in APNG"
		return result

	# Decode frames
	status_text = "Decoding frames..."
	var canvas = Image.create(result.width, result.height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))

	for i in range(fctl_list.size()):
		var fctl = fctl_list[i]
		var idat_data = frame_data_list[i]

		var fw: int = fctl["width"]
		var fh: int = fctl["height"]
		var fx: int = fctl["x_offset"]
		var fy: int = fctl["y_offset"]
		var dispose_op: int = fctl["dispose_op"]
		var blend_op: int = fctl["blend_op"]
		var delay_num: int = fctl["delay_num"]
		var delay_den: int = fctl["delay_den"]

		# Snapshot for dispose_op=2 (previous)
		var previous_canvas: Image = null
		if dispose_op == 2:
			previous_canvas = Image.new()
			previous_canvas.copy_from(canvas)

		# Build a valid PNG buffer and decode via Godot
		var png_buf = _build_png_buffer(fw, fh, bit_depth, color_type, idat_data, aux_chunks)
		var frame_img = Image.new()
		var err = frame_img.load_png_from_buffer(png_buf)
		if err != OK:
			result.error = "Failed to decode frame " + str(i) + " (error " + str(err) + ")"
			return result

		# Ensure RGBA8 format
		if frame_img.get_format() != Image.FORMAT_RGBA8:
			frame_img.convert(Image.FORMAT_RGBA8)

		# Composite onto canvas
		if blend_op == 0:  # SOURCE - overwrite
			for cy in range(fh):
				for cx in range(fw):
					var dx = fx + cx
					var dy = fy + cy
					if dx < result.width and dy < result.height and cx < frame_img.get_width() and cy < frame_img.get_height():
						canvas.set_pixel(dx, dy, frame_img.get_pixel(cx, cy))
		else:  # OVER - alpha composite
			for cy in range(fh):
				for cx in range(fw):
					var dx = fx + cx
					var dy = fy + cy
					if dx < result.width and dy < result.height and cx < frame_img.get_width() and cy < frame_img.get_height():
						var src = frame_img.get_pixel(cx, cy)
						if src.a > 0:
							var dst = canvas.get_pixel(dx, dy)
							var out_a = src.a + dst.a * (1.0 - src.a)
							if out_a > 0:
								var out_r = (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a
								var out_g = (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a
								var out_b = (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a
								canvas.set_pixel(dx, dy, Color(out_r, out_g, out_b, out_a))

		# Store composited frame
		var apng_frame = APNGFrame.new()
		apng_frame.image = Image.new()
		apng_frame.image.copy_from(canvas)

		# Calculate delay
		if delay_den == 0:
			delay_den = 100
		apng_frame.delay_ms = int(float(delay_num) * 1000.0 / float(delay_den))
		if apng_frame.delay_ms <= 0:
			apng_frame.delay_ms = 100

		result.frames.append(apng_frame)

		# Apply dispose
		match dispose_op:
			0:  # NONE - keep canvas
				pass
			1:  # BACKGROUND - clear region
				for cy in range(fh):
					for cx in range(fw):
						var dx = fx + cx
						var dy = fy + cy
						if dx < result.width and dy < result.height:
							canvas.set_pixel(dx, dy, Color(0, 0, 0, 0))
			2:  # PREVIOUS - restore snapshot
				if previous_canvas != null:
					canvas.copy_from(previous_canvas)

		progress = 0.5 + 0.5 * (float(i + 1) / float(fctl_list.size()))
		status_text = "Decoded frame " + str(i + 1) + " of " + str(fctl_list.size()) + "..."

	if result.frames.is_empty():
		result.error = "No frames decoded from APNG"
		return result

	progress = 1.0
	status_text = "Done!"
	return result

func _parse_fctl(data: PackedByteArray) -> Dictionary:
	var fctl = {}
	# sequence_number (4 bytes) - skip
	fctl["width"] = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7]
	fctl["height"] = (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11]
	fctl["x_offset"] = (data[12] << 24) | (data[13] << 16) | (data[14] << 8) | data[15]
	fctl["y_offset"] = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19]
	fctl["delay_num"] = (data[20] << 8) | data[21]
	fctl["delay_den"] = (data[22] << 8) | data[23]
	fctl["dispose_op"] = data[24]
	fctl["blend_op"] = data[25]
	return fctl
