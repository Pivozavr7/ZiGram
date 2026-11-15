// C ABI bridge between Zig (src/gui) and SDL3 + Dear ImGui.
//
// SDL structs (SDL_Event, SDL_GPUColorTargetInfo) and the C++ ImGui API are
// painful to replicate in Zig, so the GUI talks to this small interface.
// Keep every call tiny and stateless where possible; SDL/ImGui globals live
// here in static storage.

#include <SDL3/SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlgpu3.h"

namespace {

SDL_Window* g_window = nullptr;
SDL_GPUDevice* g_device = nullptr;
bool g_initialized = false;

} // namespace

extern "C" {

typedef enum {
    ZIG_GFX_EVENT_NONE = 0,
    ZIG_GFX_EVENT_QUIT,
    ZIG_GFX_EVENT_WINDOW_CLOSE,
    ZIG_GFX_EVENT_OTHER,
} zig_gfx_event;

// Copies the last SDL error into buf; returns false when there is none.
bool zig_gfx_get_error(char* buf, unsigned size)
{
    const char* error = SDL_GetError();
    if (error == nullptr || error[0] == '\0')
        return false;
    SDL_strlcpy(buf, error, size);
    return true;
}

bool zig_gfx_init(const char* title, int width, int height)
{
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD))
        return false;

    float scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
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
    style.FrameRounding = 3.0f;
    style.GrabRounding = 3.0f;
    style.ScaleAllSizes(scale);
    style.FontScaleDpi = scale;

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
    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();
    if (draw_data->DisplaySize.x <= 0.0f || draw_data->DisplaySize.y <= 0.0f)
        return;

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

// --- widget bridge -----------------------------------------------------------

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

void zig_gfx_text(const char* text)
{
    ImGui::TextUnformatted(text);
}

void zig_gfx_text_disabled(const char* text)
{
    ImGui::TextDisabled("%s", text);
}

void zig_gfx_text_error(const char* text)
{
    ImGui::TextColored(ImVec4(1.0f, 0.4f, 0.4f, 1.0f), "%s", text);
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

} // extern "C"
