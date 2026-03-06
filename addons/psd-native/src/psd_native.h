#ifndef PSD_NATIVE_H
#define PSD_NATIVE_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class PSDNative : public Object {
	GDCLASS(PSDNative, Object)

protected:
	static void _bind_methods();

public:
	static PackedByteArray decode_packbits(const PackedByteArray &data, int64_t expected_size);
	static PackedByteArray compose_rgba(const PackedByteArray &r_data, const PackedByteArray &g_data,
			const PackedByteArray &b_data, const PackedByteArray &a_data,
			int64_t pixel_count, int64_t opacity);
};

} // namespace godot

#endif // PSD_NATIVE_H
