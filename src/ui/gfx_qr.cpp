// Drawing of the login QR code.
//
// The encoder itself is the vendored qrcodegen library; this file turns its
// module matrix into rectangles.

#include <cstdint>
#include <string>
#include "gfx_shim.h"
#include "imgui.h"
#include "qrcodegen.h"

extern "C" {

// Draws a QR code for the given text; scale is the pixel size of one module.
// Returns false when the text does not fit into the supported versions.
bool zig_gfx_qr(const char* text, unsigned size, unsigned scale)
{
    if (text == nullptr || size == 0 || scale == 0)
        return false;

    static uint8_t temp_buffer[qrcodegen_BUFFER_LEN_MAX];
    static uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];

    const std::string payload(text, size);
    if (!qrcodegen_encodeText(
            payload.c_str(),
            temp_buffer,
            qrcode,
            qrcodegen_Ecc_MEDIUM,
            1,
            10,
            qrcodegen_Mask_AUTO,
            true))
        return false;

    const int modules = qrcodegen_getSize(qrcode);
    const float pixel = static_cast<float>(scale);
    const float width = static_cast<float>(modules) * pixel;

    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 available = ImGui::GetContentRegionAvail();
    const float x = origin.x + (available.x - width) * 0.5f;
    const float y = origin.y;

    ImDrawList* draw_list = ImGui::GetWindowDrawList();
    draw_list->AddRectFilled(
        ImVec2(x, y),
        ImVec2(x + width, y + width),
        IM_COL32_WHITE);
    for (int row = 0; row < modules; ++row) {
        for (int column = 0; column < modules; ++column) {
            if (!qrcodegen_getModule(qrcode, column, row))
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
