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

void zig_gfx_set_next_window_pos(float x, float y)
{
    ImGui::SetNextWindowPos(ImVec2(x, y), ImGuiCond_Once);
}

void zig_gfx_set_next_window_size(float width, float height)
{
    ImGui::SetNextWindowSize(ImVec2(width, height), ImGuiCond_Once);
}

bool zig_gfx_begin(const char* title)
{
    return ImGui::Begin(title);
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

} // extern "C"
