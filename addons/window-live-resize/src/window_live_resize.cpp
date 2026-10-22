#include "window_live_resize.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <commctrl.h>
#endif

using namespace godot;

void WindowLiveResize::_bind_methods() {
	ClassDB::bind_static_method("WindowLiveResize", D_METHOD("install", "window_handle"), &WindowLiveResize::install);
	ClassDB::bind_static_method("WindowLiveResize", D_METHOD("is_installed"), &WindowLiveResize::is_installed);
}

#ifdef _WIN32

namespace {

// Godot 4.6 DisplayServerWindows::TIMER_ID_MOVE_REDRAW.
const WPARAM GODOT_MOVE_REDRAW_TIMER = 1;
const UINT_PTR SUBCLASS_ID = 0x504C5352; // "PLSR"

HWND g_hwnd = nullptr;
bool g_in_size_move = false;

LRESULT CALLBACK live_resize_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR) {
	switch (msg) {
		case WM_ENTERSIZEMOVE:
			g_in_size_move = true;
			break;
		case WM_EXITSIZEMOVE:
			g_in_size_move = false;
			break;
		case WM_NCDESTROY:
			RemoveWindowSubclass(hwnd, live_resize_proc, SUBCLASS_ID);
			g_hwnd = nullptr;
			g_in_size_move = false;
			break;
		default:
			break;
	}
	// Godot handles the message first, so a size change is applied before the frame.
	LRESULT result = DefSubclassProc(hwnd, msg, wparam, lparam);
	if (msg == WM_WINDOWPOSCHANGED && g_in_size_move) {
		const WINDOWPOS *pos = reinterpret_cast<const WINDOWPOS *>(lparam);
		if (pos != nullptr && !(pos->flags & SWP_NOSIZE)) {
			SendMessageW(hwnd, WM_TIMER, GODOT_MOVE_REDRAW_TIMER, 0);
		}
	}
	return result;
}

} // namespace

bool WindowLiveResize::install(int64_t window_handle) {
	HWND hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(window_handle));
	if (hwnd == nullptr || !IsWindow(hwnd)) {
		return false;
	}
	if (g_hwnd == hwnd) {
		return true;
	}
	if (!SetWindowSubclass(hwnd, live_resize_proc, SUBCLASS_ID, 0)) {
		return false;
	}
	g_hwnd = hwnd;
	return true;
}

bool WindowLiveResize::is_installed() {
	return g_hwnd != nullptr;
}

#else

bool WindowLiveResize::install(int64_t) {
	return false;
}

bool WindowLiveResize::is_installed() {
	return false;
}

#endif
