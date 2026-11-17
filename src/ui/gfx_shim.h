// Shared declarations of the C ABI bridge between Zig and SDL3 + Dear ImGui.
//
// The bridge is split over a few translation units: the window and the
// frame loop, the widget calls and the QR code. They share the event kind
// and nothing else.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ZIG_GFX_EVENT_NONE = 0,
    ZIG_GFX_EVENT_QUIT,
    ZIG_GFX_EVENT_WINDOW_CLOSE,
    ZIG_GFX_EVENT_OTHER,
} zig_gfx_event;

#ifdef __cplusplus
} // extern "C"
#endif
