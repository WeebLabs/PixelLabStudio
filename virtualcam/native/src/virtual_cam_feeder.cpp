#include "virtual_cam_feeder.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef VCAM_HAS_SOFTCAM
#include "softcam.h" // vendored softcam sender API (Phase 3)
#endif

using namespace godot;

void VirtualCamFeeder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("available"), &VirtualCamFeeder::available);
	ClassDB::bind_method(D_METHOD("start", "width", "height", "fps"), &VirtualCamFeeder::start);
	ClassDB::bind_method(D_METHOD("send_frame", "data"), &VirtualCamFeeder::send_frame);
	ClassDB::bind_method(D_METHOD("stop"), &VirtualCamFeeder::stop);
}

VirtualCamFeeder::VirtualCamFeeder() :
		_cam(nullptr), _w(0), _h(0) {}

VirtualCamFeeder::~VirtualCamFeeder() {
	stop();
}

bool VirtualCamFeeder::available() const {
#ifdef VCAM_HAS_SOFTCAM
	return true;
#else
	return false;
#endif
}

bool VirtualCamFeeder::start(int width, int height, int fps) {
	_w = width;
	_h = height;
#ifdef VCAM_HAS_SOFTCAM
	// TODO(phase3): _cam = scCreateCamera(width, height, fps); return _cam != nullptr;
#endif
	return available();
}

void VirtualCamFeeder::send_frame(const PackedByteArray &data) {
#ifdef VCAM_HAS_SOFTCAM
	// TODO(phase3): if (_cam && data.size() >= _w * _h * 3) scSendFrame(_cam, data.ptr());
#endif
	(void)data;
}

void VirtualCamFeeder::stop() {
#ifdef VCAM_HAS_SOFTCAM
	// TODO(phase3): if (_cam) { scDeleteCamera(_cam); }
#endif
	_cam = nullptr;
}
