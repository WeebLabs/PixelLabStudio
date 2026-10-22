#ifndef WINDOW_LIVE_RESIZE_H
#define WINDOW_LIVE_RESIZE_H

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

// Keeps the app drawing while a window edge is dragged quickly (Windows).
//
// During a drag Windows runs its own modal loop, and Godot only gets a frame when
// the timer it starts on WM_ENTERSIZEMOVE fires. WM_TIMER is the lowest-priority
// message, so a fast drag (a steady stream of size changes) starves it and the
// app freezes for up to half a second at a time. This subclasses the window and,
// after each size change inside a drag, hands Godot that same timer message, so
// it runs one frame through its own WM_TIMER path (which already guards against
// re-entry with Main::is_iterating()).
//
// Relies on Godot 4.6's DisplayServerWindows: the redraw timer is created with
// nIDEvent TIMER_ID_MOVE_REDRAW (1), and move_timer_id is 0 outside a drag, so
// the message is ignored at any other time. Other platforms: install() is a no-op.
class WindowLiveResize : public RefCounted {
	GDCLASS(WindowLiveResize, RefCounted)

protected:
	static void _bind_methods();

public:
	// Subclass the native window (DisplayServer.window_get_native_handle). Returns
	// true once the hook is in place; false off Windows or on failure.
	static bool install(int64_t window_handle);
	static bool is_installed();
};

} // namespace godot

#endif // WINDOW_LIVE_RESIZE_H
