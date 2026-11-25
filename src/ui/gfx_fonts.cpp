// System fonts for the atlas: a base face with merged emoji and CJK faces.
//
// This runs before the first frame: the atlas locks once ImGui draws.

#include "gfx_shim.h"
#include "imgui.h"
#include "misc/freetype/imgui_freetype.h"

namespace {

// NotoColorEmoji ships a single CBDT strike of 109 px per em (136x128
// bitmap); FreeType accepts request heights within half a pixel of it and
// fails on anything further away.
const float kEmojiStrikePx = 109.0f;

// Codepoints NotoColorEmoji paints beyond the built-in ranges. Lazy baking
// does not consult the ranges; they matter for the legacy preload path.
const ImWchar kEmojiRanges[] = {
    0x00A9, 0x00AE,   // (c) (r)
    0x2600, 0x27BF,   // miscellaneous symbols and dingbats
    0x2B00, 0x2BFF,   // miscellaneous symbols and arrows
    0xFE0F, 0xFE0F,   // variation selector-16
    0x1F000, 0x1FAFF, // emoji blocks
    0,
};

// The pixel size ImGui bakes the font at: the base size multiplied by the
// global scales and rounded the way ImGui rounds it before rasterizing.
float bakedFontSize(const ImGuiStyle& style)
{
    const float size = style.FontSizeBase * style.FontScaleMain * style.FontScaleDpi;
    return (float)(int)(size + 0.5f); // IM_ROUND
}

} // namespace

// Loads the base font and merges the emoji and CJK faces into it. The emoji
// face has a single strike, so its rasterizer density asks FreeType for
// exactly that size whatever the UI font size is; `pixel_density` scales the
// request the way ImGui scales every glyph for the window framebuffer.
void zig_gfx_load_fonts(const zig_gfx_fonts* fonts, float pixel_density)
{
    if (fonts == nullptr || fonts->base == nullptr)
        return; // ImGui draws its built-in default font.

    ImGuiStyle& style = ImGui::GetStyle();
    const float font_size = style.FontSizeBase;
    ImFontAtlas* atlas = ImGui::GetIO().Fonts;

    ImFontConfig base_cfg;
    base_cfg.Flags |= ImFontFlags_NoLoadError;
    if (atlas->AddFontFromFileTTF(fonts->base, font_size, &base_cfg,
            atlas->GetGlyphRangesCyrillic()) == nullptr)
        return;

    if (fonts->emoji != nullptr)
    {
        const float baked = bakedFontSize(style) * pixel_density;
        ImFontConfig cfg;
        cfg.Flags |= ImFontFlags_NoLoadError;
        cfg.MergeMode = true;
        if (baked > 0.0f)
            cfg.RasterizerDensity = kEmojiStrikePx / baked;
        cfg.FontLoaderFlags = ImGuiFreeTypeLoaderFlags_LoadColor | ImGuiFreeTypeLoaderFlags_Bitmap;
        atlas->AddFontFromFileTTF(fonts->emoji, font_size, &cfg, kEmojiRanges);
    }

    if (fonts->cjk != nullptr)
    {
        ImFontConfig cfg;
        cfg.Flags |= ImFontFlags_NoLoadError;
        cfg.MergeMode = true;
        cfg.FontNo = 0; // first face of the .ttc collection
        atlas->AddFontFromFileTTF(fonts->cjk, font_size, &cfg,
            atlas->GetGlyphRangesChineseFull());
    }
}
