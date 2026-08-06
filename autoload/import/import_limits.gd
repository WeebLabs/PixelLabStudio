class_name ImportLimits
extends RefCounted

## Resource budgets shared by binary image importers. These are deliberately
## lower than the formats' theoretical limits: imported assets must still be
## decoded, composited, duplicated, and uploaded as textures by the app.
const MAX_FILE_BYTES := 512 * 1024 * 1024
const MAX_CHUNK_BYTES := 256 * 1024 * 1024
const MAX_IMAGE_DIMENSION := 16384
const MAX_IMAGE_PIXELS := 64 * 1024 * 1024
const MAX_DECODED_BYTES := 512 * 1024 * 1024
const MAX_LAYERS := 10000
const MAX_FRAMES := 4096
const MAX_CHANNELS := 64

static func section_fits(position: int, length: int, boundary: int) -> bool:
	return position >= 0 and length >= 0 and position <= boundary and length <= boundary - position

static func dimensions_valid(width: int, height: int) -> bool:
	if width <= 0 or height <= 0:
		return false
	if width > MAX_IMAGE_DIMENSION or height > MAX_IMAGE_DIMENSION:
		return false
	return width <= MAX_IMAGE_PIXELS / height

static func decoded_images_fit(width: int, height: int, count: int) -> bool:
	if not dimensions_valid(width, height) or count <= 0 or count > MAX_FRAMES:
		return false
	var bytes_per_image := width * height * 4
	return bytes_per_image <= MAX_DECODED_BYTES / count

static func count_valid(count: int, maximum: int) -> bool:
	return count > 0 and count <= maximum
