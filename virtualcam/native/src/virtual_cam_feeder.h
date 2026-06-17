#ifndef VIRTUAL_CAM_FEEDER_H
#define VIRTUAL_CAM_FEEDER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

// Native bridge to the softcam DirectShow virtual-camera sender (Windows).
//
// Phase 2 scaffold: the class + method surface compile against godot-cpp on every
// platform so the GDExtension loads everywhere (available() just reports false off
// Windows). The real softcam sender calls land behind VCAM_HAS_SOFTCAM in Phase 3,
// once softcam's source is vendored into the Windows build.
class VirtualCamFeeder : public RefCounted {
	GDCLASS(VirtualCamFeeder, RefCounted)

protected:
	static void _bind_methods();

public:
	VirtualCamFeeder();
	~VirtualCamFeeder();

	// Whether the native sender is compiled in and usable on this platform.
	bool available() const;
	// Create (or resize) the virtual camera. Returns true on success.
	bool start(int width, int height, int fps);
	// Push one frame: width*height*3 bytes, 24-bit BGR, bottom-up (DIB order).
	void send_frame(const PackedByteArray &data);
	// Tear down the sender.
	void stop();

private:
	void *_cam; // softcam scCamera handle (opaque), when VCAM_HAS_SOFTCAM
	int _w;
	int _h;
};

} // namespace godot

#endif // VIRTUAL_CAM_FEEDER_H
