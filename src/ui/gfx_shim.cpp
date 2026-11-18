// Window, GPU device, events and the frame loop of the C ABI bridge.
//
// This file owns the SDL objects and the Dear ImGui context: both live and
// die together with the window. The widget calls and the QR code have their
// own translation units.

#include <SDL3/SDL.h>
#include <cstdint>
#include "gfx_shim.h"
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlgpu3.h"

namespace {

SDL_Window* g_window = nullptr;
SDL_GPUDevice* g_device = nullptr;
bool g_initialized = false;

// The display scale of the primary monitor: the theme sizes are logical
// pixels and are multiplied by it.
float g_dpi_scale = 1.0f;

// The theme applied last, kept for the widget calls.
zig_gfx_theme g_theme = {};

// Frames to skip after a window resize: the swapchain still carries the old
// size while ImGui already renders with the new one, and SDL asserts when
// the viewport exceeds the render target.
int g_resize_frames_pending = 0;
int g_render_width = 0;
int g_render_height = 0;

ImVec4 vec4(const zig_gfx_color& color)
{
    return ImVec4(color.r, color.g, color.b, color.a);
}

ImVec4 withAlpha(const ImVec4& color, float alpha)
{
    return ImVec4(color.x, color.y, color.z, alpha);
}

// The theme drives the style: colors, rounding, spacing, padding and the
// font scale. The sizes are logical pixels, multiplied by the display
// scale the same way ScaleAllSizes treats the defaults.
void applyTheme(const zig_gfx_theme& theme)
{
    g_theme = theme;

    ImGuiStyle& style = ImGui::GetStyle();
    style.FrameRounding = theme.rounding * g_dpi_scale;
    style.GrabRounding = theme.rounding * g_dpi_scale;
    style.ItemSpacing =
        ImVec2(theme.spacing.x * g_dpi_scale, theme.spacing.y * g_dpi_scale);
    style.WindowPadding = ImVec2(theme.padding * g_dpi_scale, theme.padding * g_dpi_scale);
    style.FontScaleMain = theme.font_size / style.FontSizeBase;

    // Buttons and selections take their color from the accent; the states
    // differ in opacity the way the stock dark style does.
    const ImVec4 accent = vec4(theme.accent);
    ImVec4* colors = style.Colors;
    colors[ImGuiCol_Text] = vec4(theme.text);
    colors[ImGuiCol_TextDisabled] = vec4(theme.text_disabled);
    colors[ImGuiCol_WindowBg] = vec4(theme.surface);
    colors[ImGuiCol_ChildBg] = vec4(theme.surface);
    colors[ImGuiCol_Button] = withAlpha(accent, 0.40f);
    colors[ImGuiCol_ButtonHovered] = accent;
    colors[ImGuiCol_ButtonActive] = accent;
    colors[ImGuiCol_Header] = withAlpha(accent, 0.31f);
    colors[ImGuiCol_HeaderHovered] = withAlpha(accent, 0.80f);
    colors[ImGuiCol_HeaderActive] = accent;
    colors[ImGuiCol_CheckMark] = accent;
    colors[ImGuiCol_SliderGrab] = accent;
    colors[ImGuiCol_SliderGrabActive] = accent;
    colors[ImGuiCol_NavCursor] = withAlpha(accent, 0.80f);
}

} // namespace

extern "C" {

// Copies the last SDL error into buf; returns false when there is none.
bool zig_gfx_get_error(char* buf, unsigned size)
{
    const char* error = SDL_GetError();
    if (error == nullptr || error[0] == '\0')
        return false;
    SDL_strlcpy(buf, error, size);
    return true;
}

bool zig_gfx_init(const char* title, int width, int height, const zig_gfx_theme* theme)
{
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD))
        return false;

    float scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
    g_dpi_scale = scale;
    g_window = SDL_CreateWindow(
        title,
        (int)(width * scale),
        (int)(height * scale),
        SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
    if (g_window == nullptr)
        return false;
    SDL_SetWindowPosition(g_window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    SDL_ShowWindow(g_window);

    g_device = SDL_CreateGPUDevice(
        SDL_GPU_SHADERFORMAT_SPIRV | SDL_GPU_SHADERFORMAT_DXIL |
            SDL_GPU_SHADERFORMAT_MSL | SDL_GPU_SHADERFORMAT_METALLIB,
        true,
        nullptr);
    if (g_device == nullptr)
        return false;
    if (!SDL_ClaimWindowForGPUDevice(g_device, g_window))
        return false;
    SDL_SetGPUSwapchainParameters(
        g_device, g_window, SDL_GPU_SWAPCHAINCOMPOSITION_SDR, SDL_GPU_PRESENTMODE_VSYNC);

    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.IniFilename = nullptr; // keep the working directory clean

    ImGuiStyle& style = ImGui::GetStyle();
    ImGui::StyleColorsDark();
    style.ScaleAllSizes(scale);
    style.FontScaleDpi = scale;
    if (theme != nullptr)
        applyTheme(*theme);

    ImGui_ImplSDL3_InitForSDLGPU(g_window);

    ImGui_ImplSDLGPU3_InitInfo init_info = {};
    init_info.Device = g_device;
    init_info.ColorTargetFormat = SDL_GetGPUSwapchainTextureFormat(g_device, g_window);
    init_info.MSAASamples = SDL_GPU_SAMPLECOUNT_1;
    init_info.SwapchainComposition = SDL_GPU_SWAPCHAINCOMPOSITION_SDR;
    init_info.PresentMode = SDL_GPU_PRESENTMODE_VSYNC;
    ImGui_ImplSDLGPU3_Init(&init_info);

    g_initialized = true;
    return true;
}

const zig_gfx_theme* zig_gfx_get_theme(void)
{
    return &g_theme;
}

void zig_gfx_quit(void)
{
    if (!g_initialized)
        return;
    ImGui_ImplSDLGPU3_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();
    if (g_window != nullptr)
    {
        SDL_DestroyWindow(g_window);
        g_window = nullptr;
    }
    if (g_device != nullptr)
    {
        SDL_DestroyGPUDevice(g_device);
        g_device = nullptr;
    }
    SDL_Quit();
    g_initialized = false;
}

bool zig_gfx_minimized(void)
{
    return (SDL_GetWindowFlags(g_window) & SDL_WINDOW_MINIMIZED) != 0;
}

void zig_gfx_delay(unsigned ms)
{
    SDL_Delay(ms);
}

// Polls one event, feeds it to ImGui and reports its kind.
zig_gfx_event zig_gfx_poll_event(void)
{
    SDL_Event event;
    if (!SDL_PollEvent(&event))
        return ZIG_GFX_EVENT_NONE;
    ImGui_ImplSDL3_ProcessEvent(&event);
    if (event.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED ||
        event.type == SDL_EVENT_WINDOW_RESIZED)
    {
        // Two frames: one for the swapchain to be rebuilt, one for the new
        // size to reach the render target.
        g_resize_frames_pending = 2;
    }
    if (event.type == SDL_EVENT_QUIT)
        return ZIG_GFX_EVENT_QUIT;
    if (event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED &&
        event.window.windowID == SDL_GetWindowID(g_window))
        return ZIG_GFX_EVENT_WINDOW_CLOSE;
    return ZIG_GFX_EVENT_OTHER;
}

void zig_gfx_new_frame(void)
{
    ImGui_ImplSDLGPU3_NewFrame();
    ImGui_ImplSDL3_NewFrame();
    ImGui::NewFrame();
}

// Renders the prepared ImGui frame and submits the GPU command buffer.
void zig_gfx_render(float clear_r, float clear_g, float clear_b, float clear_a)
{
    // The ImGui frame has to be closed every time, even when the GPU work is
    // skipped: otherwise ImGui aborts on the next NewFrame.
    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();
    if (draw_data->DisplaySize.x <= 0.0f || draw_data->DisplaySize.y <= 0.0f)
        return;

    int window_width = 0;
    int window_height = 0;
    if (!SDL_GetWindowSizeInPixels(g_window, &window_width, &window_height))
        return;

    if (g_resize_frames_pending > 0 ||
        window_width != g_render_width || window_height != g_render_height)
    {
        // The swapchain still carries the old size: rebuild it and skip the
        // GPU work of this frame, otherwise the viewport would exceed the
        // render target.
        g_resize_frames_pending -= 1;
        if (g_resize_frames_pending < 0)
            g_resize_frames_pending = 0;
        g_render_width = window_width;
        g_render_height = window_height;
        SDL_SetGPUSwapchainParameters(
            g_device, g_window, SDL_GPU_SWAPCHAINCOMPOSITION_SDR, SDL_GPU_PRESENTMODE_VSYNC);
        return;
    }

    SDL_GPUCommandBuffer* command_buffer = SDL_AcquireGPUCommandBuffer(g_device);
    SDL_GPUTexture* swapchain_texture = nullptr;
    SDL_WaitAndAcquireGPUSwapchainTexture(
        command_buffer, g_window, &swapchain_texture, nullptr, nullptr);
    if (swapchain_texture == nullptr)
    {
        SDL_SubmitGPUCommandBuffer(command_buffer);
        return;
    }

    SDL_GPUColorTargetInfo target_info = {};
    target_info.texture = swapchain_texture;
    target_info.clear_color = SDL_FColor{clear_r, clear_g, clear_b, clear_a};
    target_info.load_op = SDL_GPU_LOADOP_CLEAR;
    target_info.store_op = SDL_GPU_STOREOP_STORE;
    target_info.mip_level = 0;
    target_info.layer_or_depth_plane = 0;
    target_info.cycle = false;

    // This is mandatory before any render pass: it opens its own copy pass
    // to upload the vertex/index buffers.
    ImGui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer);

    SDL_GPURenderPass* render_pass =
        SDL_BeginGPURenderPass(command_buffer, &target_info, 1, nullptr);
    ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass);
    SDL_EndGPURenderPass(render_pass);
    SDL_SubmitGPUCommandBuffer(command_buffer);
}

} // extern "C"
