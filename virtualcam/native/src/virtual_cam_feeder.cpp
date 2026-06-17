#include "virtual_cam_feeder.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef VCAM_HAS_SOFTCAM
#include "SenderAPI.h" // softcam sender API: softcam::sender::CreateCamera/SendFrame/DeleteCamera
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
	stop();
	_w = width;
	_h = height;
#ifdef VCAM_HAS_SOFTCAM
	_cam = softcam::sender::CreateCamera(width, height, (float)fps);
	return _cam != nullptr;
#else
	return false;
#endif
}

void VirtualCamFeeder::send_frame(const PackedByteArray &data) {
#ifdef VCAM_HAS_SOFTCAM
	// FrameBuffer expects tightly-packed width*height*3 (it adds DIB row stride itself).
	if (_cam != nullptr && data.size() >= (int64_t)_w * (int64_t)_h * 3) {
		softcam::sender::SendFrame(_cam, data.ptr());
	}
#else
	(void)data;
#endif
}

void VirtualCamFeeder::stop() {
#ifdef VCAM_HAS_SOFTCAM
	if (_cam != nullptr) {
		softcam::sender::DeleteCamera(_cam);
	}
#endif
	_cam = nullptr;
}
