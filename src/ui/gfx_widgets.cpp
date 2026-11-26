// The Dear ImGui widget bridge: one small C function per widget.
//
// Every function here is a thin call into ImGui; the layout decisions live
// in Zig, in the screens and the widgets.

#include <cstdint>
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

// The height of one framed widget (a button, an input): the screens reserve
// it when they pin a row to the bottom of a pane.
float zig_gfx_frame_height(void)
{
    return ImGui::GetFrameHeight();
}

} // extern "C"
