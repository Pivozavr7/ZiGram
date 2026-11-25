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

// Theme values the Zig side passes over. The layout matches `theme.Tokens`
// in src/ui/theme/tokens.zig; change both together.
typedef struct {
    float r, g, b, a;
} zig_gfx_color;

typedef struct {
    float x, y;
} zig_gfx_size;

typedef struct {
    zig_gfx_color background;
    zig_gfx_color surface;
    zig_gfx_color text;
    zig_gfx_color text_disabled;
    zig_gfx_color error_color;
    zig_gfx_color accent;
    zig_gfx_size spacing;
    float rounding;
    float padding;
    float font_size;
    float panel_width;
    float panel_height;
    float composer_height;
} zig_gfx_theme;

// Font files the Zig side located for the atlas; NULL entries skip a
// source. The layout matches `fonts.Fonts` in src/ui/fonts.zig; change
// both together.
typedef struct {
    const char* base;
    const char* cjk;
    const char* emoji;
} zig_gfx_fonts;

// Shim-internal: loads the base font and merges the emoji and CJK faces.
// zig_gfx_init calls it after the theme is applied; Zig never calls it.
void zig_gfx_load_fonts(const zig_gfx_fonts* fonts, float pixel_density);

// The theme applied last; valid once zig_gfx_init has returned.
const zig_gfx_theme* zig_gfx_get_theme(void);

#ifdef __cplusplus
} // extern "C"
#endif
