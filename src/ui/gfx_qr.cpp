// Drawing of the login QR code.
//
// The encoder lives in Zig; this file only turns the module matrix into
// rectangles. The matrix comes row-major with `count * count` entries, `true`
// for the dark modules.

#include <cstdint>
#include "gfx_shim.h"
#include "imgui.h"

namespace {

// The largest pixel size of a single module before the code would overflow
// the window.
constexpr float kMaxModulePixels = 16.0f;

// Picks the whole-pixel size of one module that fits the available width.
float chooseScale(int count, float available)
{
    const float fit = available / static_cast<float>(count);
    if (fit < 1.0f)
        return 1.0f;
    if (fit > kMaxModulePixels)
        return kMaxModulePixels;
    return fit;
}

} // namespace

extern "C" {

// Draws an encoded QR code; scale is the pixel size of one module, or zero
// to pick the size that fits the window. Returns false when the matrix is
// empty or unreasonably large.
bool zig_gfx_draw_qr(const bool* modules, int count, int scale)
{
    if (modules == nullptr || count <= 0 || count > 4096)
        return false;

    const ImVec2 available = ImGui::GetContentRegionAvail();
    const float pixel = (scale > 0)
        ? static_cast<float>(scale)
        : chooseScale(count, available.x);
    const float width = static_cast<float>(count) * pixel;

    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const float x = origin.x + (available.x - width) * 0.5f;
    const float y = origin.y;

    ImDrawList* draw_list = ImGui::GetWindowDrawList();
    draw_list->AddRectFilled(
        ImVec2(x, y),
        ImVec2(x + width, y + width),
        IM_COL32_WHITE);
    for (int row = 0; row < count; ++row) {
        for (int column = 0; column < count; ++column) {
            if (!modules[row * count + column])
                continue;
            draw_list->AddRectFilled(
                ImVec2(x + static_cast<float>(column) * pixel,
                    y + static_cast<float>(row) * pixel),
                ImVec2(x + static_cast<float>(column + 1) * pixel,
                    y + static_cast<float>(row + 1) * pixel),
                IM_COL32_BLACK);
        }
    }

    ImGui::Dummy(ImVec2(width, width));
    return true;
}

} // extern "C"
