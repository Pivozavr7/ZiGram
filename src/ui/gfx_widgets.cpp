// The Dear ImGui widget bridge: one small C function per widget.
//
// Every function here is a thin call into ImGui; the layout decisions live
// in Zig, in the screens and the widgets.

#include <cstdint>
#include <cfloat>
#include <cstdio>
#include "gfx_shim.h"
#include "imgui.h"

namespace {

ImVec4 vec4(const zig_gfx_color& color)
{
    return ImVec4(color.r, color.g, color.b, color.a);
}

} // namespace

extern "C" {

// The root window: fills the whole client area and has no decoration of its
// own, so the SDL window frame is the only frame the user sees.
bool zig_gfx_begin(const char* title)
{
    ImGuiIO& io = ImGui::GetIO();
    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f), ImGuiCond_Always);
    ImGui::SetNextWindowSize(io.DisplaySize, ImGuiCond_Always);
    return ImGui::Begin(
        title,
        nullptr,
        ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
            ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus |
            ImGuiWindowFlags_NoNavFocus);
}

void zig_gfx_end(void)
{
    ImGui::End();
}

void zig_gfx_text(const char* text, unsigned size)
{
    ImGui::TextUnformatted(text, text + size);
}

void zig_gfx_text_disabled(const char* text, unsigned size)
{
    ImGui::TextDisabled("%.*s", (int)size, text);
}

void zig_gfx_text_error(const char* text, unsigned size)
{
    ImGui::TextColored(vec4(zig_gfx_get_theme()->error_color), "%.*s", (int)size, text);
}

void zig_gfx_separator(void)
{
    ImGui::Separator();
}

bool zig_gfx_button(const char* label)
{
    return ImGui::Button(label);
}

bool zig_gfx_input_text(const char* label, char* buf, unsigned size)
{
    return ImGui::InputText(label, buf, size);
}

bool zig_gfx_input_text_password(const char* label, char* buf, unsigned size)
{
    return ImGui::InputText(label, buf, size, ImGuiInputTextFlags_Password);
}

// Opens a child region; a size of 0 means "use the remaining space".
bool zig_gfx_begin_child(const char* label, float size_x, float size_y)
{
    return ImGui::BeginChild(label, ImVec2(size_x, size_y), ImGuiChildFlags_None);
}

void zig_gfx_end_child(void)
{
    ImGui::EndChild();
}

bool zig_gfx_selectable(const char* label, bool selected)
{
    return ImGui::Selectable(label, selected);
}

// A multi line input of the given height in pixels.
bool zig_gfx_input_text_multiline(
    const char* label, char* buf, unsigned size, float height)
{
    return ImGui::InputTextMultiline(
        label,
        buf,
        size,
        ImVec2(0.0f, height),
        ImGuiInputTextFlags_AllowTabInput);
}

void zig_gfx_same_line(void)
{
    ImGui::SameLine();
}

// A progress bar across the remaining width, with a percentage overlay.
void zig_gfx_progress_bar(float fraction)
{
    char overlay[16];
    snprintf(overlay, sizeof(overlay), "%d%%", (int)(fraction * 100.0f + 0.5f));
    ImGui::ProgressBar(fraction, ImVec2(-FLT_MIN, 0.0f), overlay);
}

// The size of a text block; a wrap width below 0 disables wrapping.
void zig_gfx_text_size(
    const char* text, unsigned size, float wrap_width, float* out_w, float* out_h)
{
    const ImVec2 measured = ImGui::CalcTextSize(text, text + size, false, wrap_width);
    *out_w = measured.x;
    *out_h = measured.y;
}

// A filled rounded rectangle; used for the message bubbles.
void zig_gfx_rect_filled(
    float min_x, float min_y, float max_x, float max_y, zig_gfx_color color, float rounding)
{
    ImGui::GetWindowDrawList()->AddRectFilled(
        ImVec2(min_x, min_y),
        ImVec2(max_x, max_y),
        ImGui::ColorConvertFloat4ToU32(vec4(color)),
        rounding);
}

// An invisible placeholder of the given height; keeps the scroll range of
// a virtualized list correct.
void zig_gfx_dummy(float height)
{
    ImGui::Dummy(ImVec2(0.0f, height));
}

// Vertical scroll and inner height of the current window.
float zig_gfx_scroll_y(void)
{
    return ImGui::GetScrollY();
}

float zig_gfx_window_height(void)
{
    return ImGui::GetWindowHeight();
}

// Moves the vertical scroll of the current window; used to follow new
// messages at the bottom of a conversation.
void zig_gfx_set_scroll_y(float value)
{
    ImGui::SetScrollY(value);
}

// Where the cursor stands in screen coordinates, and how much horizontal
// room is left in the current region: the bubbles measure against both.
void zig_gfx_cursor_screen_pos(float* out_x, float* out_y)
{
    const ImVec2 pos = ImGui::GetCursorScreenPos();
    *out_x = pos.x;
    *out_y = pos.y;
}

float zig_gfx_avail_width(void)
{
    return ImGui::GetContentRegionAvail().x;
}

// Moves the horizontal cursor inside the current region; a bubble that is
// right aligned starts from `value`.
void zig_gfx_set_cursor_x(float value)
{
    ImGui::SetCursorPosX(value);
}

// Draws text at a screen position without taking layout space; the bubble
// draws its own background and needs the text exactly inside it.
void zig_gfx_text_at(float x, float y, const char* text, unsigned size)
{
    ImGui::GetWindowDrawList()->AddText(
        ImVec2(x, y),
        ImGui::ColorConvertFloat4ToU32(vec4(zig_gfx_get_theme()->text)),
        text,
        text + size);
}

// The height of one framed widget (a button, an input): the screens reserve
// it when they pin a row to the bottom of a pane.
float zig_gfx_frame_height(void)
{
    return ImGui::GetFrameHeight();
}

} // extern "C"
