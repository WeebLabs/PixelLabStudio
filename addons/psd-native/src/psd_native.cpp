#include "psd_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cstring>

namespace godot {

void PSDNative::_bind_methods() {
	ClassDB::bind_static_method("PSDNative", D_METHOD("decode_packbits", "data", "expected_size"), &PSDNative::decode_packbits);
	ClassDB::bind_static_method("PSDNative", D_METHOD("compose_rgba", "r_data", "g_data", "b_data", "a_data", "pixel_count", "opacity"), &PSDNative::compose_rgba);
}

PackedByteArray PSDNative::decode_packbits(const PackedByteArray &data, int64_t expected_size) {
	PackedByteArray result;
	if (expected_size <= 0) {
		return result;
	}
	result.resize(expected_size);

	const uint8_t *src = data.ptr();
	uint8_t *dst = result.ptrw();
	int64_t pos = 0;
	int64_t out_pos = 0;
	int64_t data_size = data.size();

	while (pos < data_size && out_pos < expected_size) {
		uint8_t n = src[pos++];

		if (n < 128) {
			// Literal run: copy next n+1 bytes
			int64_t count = n + 1;
			int64_t remaining_src = data_size - pos;
			int64_t remaining_dst = expected_size - out_pos;
			if (count > remaining_src) count = remaining_src;
			if (count > remaining_dst) count = remaining_dst;
			memcpy(dst + out_pos, src + pos, count);
			pos += count;
			out_pos += count;
		} else if (n > 128) {
			// Repeated run: repeat next byte (257 - n) times
			if (pos >= data_size) break;
			uint8_t val = src[pos++];
			int64_t count = 257 - n;
			int64_t remaining_dst = expected_size - out_pos;
			if (count > remaining_dst) count = remaining_dst;
			memset(dst + out_pos, val, count);
			out_pos += count;
		}
		// n == 128: no-op
	}

	return result;
}

PackedByteArray PSDNative::compose_rgba(const PackedByteArray &r_data, const PackedByteArray &g_data,
		const PackedByteArray &b_data, const PackedByteArray &a_data,
		int64_t pixel_count, int64_t opacity) {
	PackedByteArray result;
	if (pixel_count <= 0) {
		return result;
	}
	result.resize(pixel_count * 4);

	uint8_t *dst = result.ptrw();

	const uint8_t *r_ptr = r_data.ptr();
	const uint8_t *g_ptr = g_data.ptr();
	const uint8_t *b_ptr = b_data.ptr();
	const uint8_t *a_ptr = a_data.ptr();

	bool has_r = r_data.size() >= pixel_count;
	bool has_g = g_data.size() >= pixel_count;
	bool has_b = b_data.size() >= pixel_count;
	bool has_a = a_data.size() >= pixel_count;

	if (has_r && has_g && has_b && has_a && opacity == 255) {
		// Fast path: all channels present, full opacity
		for (int64_t p = 0; p < pixel_count; p++) {
			int64_t idx = p * 4;
			dst[idx]     = r_ptr[p];
			dst[idx + 1] = g_ptr[p];
			dst[idx + 2] = b_ptr[p];
			dst[idx + 3] = a_ptr[p];
		}
	} else if (has_r && has_g && has_b && has_a) {
		// All channels, partial opacity
		for (int64_t p = 0; p < pixel_count; p++) {
			int64_t idx = p * 4;
			dst[idx]     = r_ptr[p];
			dst[idx + 1] = g_ptr[p];
			dst[idx + 2] = b_ptr[p];
			dst[idx + 3] = (uint8_t)((a_ptr[p] * opacity) / 255);
		}
	} else if (has_r && has_g && has_b && !has_a) {
		// RGB, no alpha — fully opaque at layer opacity
		uint8_t opa = (uint8_t)opacity;
		for (int64_t p = 0; p < pixel_count; p++) {
			int64_t idx = p * 4;
			dst[idx]     = r_ptr[p];
			dst[idx + 1] = g_ptr[p];
			dst[idx + 2] = b_ptr[p];
			dst[idx + 3] = opa;
		}
	} else {
		// General fallback: missing channels
		for (int64_t p = 0; p < pixel_count; p++) {
			int64_t idx = p * 4;
			dst[idx]     = has_r ? r_ptr[p] : 0;
			dst[idx + 1] = has_g ? g_ptr[p] : 0;
			dst[idx + 2] = has_b ? b_ptr[p] : 0;
			uint8_t alpha = has_a ? a_ptr[p] : 255;
			dst[idx + 3] = (uint8_t)((alpha * opacity) / 255);
		}
	}

	return result;
}

} // namespace godot
