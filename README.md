<div align="center">

# ⚡ ZiGram

**A fast, native, hackable Telegram client written in Zig.**
Immediate-mode GPU interface. Zero Electron. Zero Qt. Three themes. Everything configurable.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-0.17.x-f7a41d.svg?logo=zig&logoColor=white)](https://ziglang.org)
[![Platform](https://img.shields.io/badge/platform-Linux-informational.svg?logo=linux&logoColor=white)](#requirements)
[![Status](https://img.shields.io/badge/status-pre--alpha-red.svg)](#status)

</div>

---

## Status

> **ZiGram is in early development. There is nothing to download or run yet.**
> The architecture is settled and work on the core is starting. This README describes where the project is going; items are marked **planned** until they actually exist. Watch the repo or check the [roadmap](#roadmap).

## Why ZiGram

Telegram's official desktop client is great, but it is a big Qt/C++ codebase that is hard to modify and hard to build. Other clients are web wrappers. ZiGram takes a different route:

- **Native and small.** One Zig binary plus Telegram's own TDLib. No browser engine, no Qt.
- **Fast by construction.** Immediate-mode UI ([Dear ImGui](https://github.com/ocornut/imgui)) rendered through SDL3's GPU API.
- **Hackable.** Themes, layout and keybinds are plain [`.zon`](https://ziglang.org/) files, loaded at runtime. No recompiling to change a color.
- **Clean separation.** The Telegram logic lives in a GUI-free core library and has its own headless CLI. The UI is just a client of that core.
- **Honest about TDLib.** It uses the official, battle-tested TDLib for protocol, encryption, sync and caching, so ZiGram does not reimplement MTProto.

## Planned features

| | |
|---|---|
| 💬 **Chats** | Private chats and groups first; channels, topics and secret chats later |
| 🎨 **Three designs** | **MD3** (Material 3), **Linear** (dense, minimal), **Flat** (tdesktop-inspired, refined) |
| 🎛️ **Deep customization** | Colors, rounding, density, fonts, panel widths, all in config files |
| ⌨️ **Keybinds** | tdesktop-compatible defaults, fully remappable, optional vim-style navigation |
| 🪟 **Layouts** | Classic two-pane first, then several chats side by side |
| 🔔 **Notifications** | Native Linux notifications over D-Bus |
| 🌍 **Text** | Cyrillic, CJK, color emoji, IME input |
| 🖼️ **Media** | Photos, then stickers, voice messages, video notes, GIFs |

Not planned for the first releases: calls, bots UI polish, RTL scripts (Dear ImGui does not support them).

<!--
## Screenshots
Add screenshots here once the UI exists.
-->

## Architecture

```
┌──────────────────────────────────────────────┐
│  ui/    Dear ImGui · SDL3 GPU · themes       │   MVP 1
├──────────────────────────────────────────────┤
│  app/   application state · event queue      │
├──────────────────────────────────────────────┤
│  core/  Telegram logic, no GUI imports       │   MVP 0
│         td.zig    runtime-loaded libtdjson   │
│         auth.zig  authorization state machine│
│         store.zig chats · messages · users   │
├──────────────────────────────────────────────┤
│  libtdjson.so   (official TDLib, JSON API)   │
└──────────────────────────────────────────────┘
```

Design decisions worth knowing:

- **TDLib is loaded at runtime** with `std.DynLib`. No C header and no link-time dependency, so ZiGram builds without TDLib present, and you can point it at any compatible `libtdjson.so`.
- **One receiver thread** calls `td_receive` and feeds a queue. The UI thread drains it once per frame.
- **The UI never talks to TDLib directly**; it reads the store and sends commands.

## Requirements

- **Linux** (developed on Arch; Wayland and X11 through SDL3)
- **Zig 0.17.x** (developed on 0.17.1)
- **SDL3**, **FreeType**, **fontconfig**, **D-Bus** development libraries
- **TDLib 1.8.x** `libtdjson.so`. You do **not** need to compile it, see below.
- Your own Telegram **`api_id` / `api_hash`** from [my.telegram.org](https://my.telegram.org)

On Arch:

```sh
sudo pacman -S zig sdl3 freetype2 fontconfig dbus
```

## Getting TDLib without compiling it

TDLib takes a long time and a lot of RAM to build. ZiGram avoids that: the repository ships a small script that downloads a **prebuilt** `libtdjson.so` and verifies it against a pinned checksum.

```sh
./scripts/fetch-tdlib.sh
```

How it works:

1. Reads the pinned version and `sha256` from [`tdlib.lock`](tdlib.lock) in the repo root
2. Fetches the prebuilt library from the [`prebuilt-tdlib`](https://www.npmjs.com/package/prebuilt-tdlib) npm package (statically linked against OpenSSL and zlib)
3. Refuses to continue if the checksum does not match
4. Places the library in `vendor/tdlib/` (git-ignored)

Prefer your own copy? Set `tdlib_path` in the config or `ZIGRAM_TDLIB=/path/to/libtdjson.so`. ZiGram searches, in order: config, environment, `vendor/tdlib/`, `~/.local/share/zigram/`, then system paths. A system package such as the AUR's `telegram-tdlib` works too.

> The prebuilt binary is third-party. Pinning the checksum protects you from silent changes, but if you want full control, build TDLib yourself or use your distro's package.

## Configuration

ZiGram needs **your own API credentials**. Create an application at [my.telegram.org](https://my.telegram.org), then write `~/.config/zigram/config.zon` (planned format):

```zig
.{
    .api_id = 12345,
    .api_hash = "your_api_hash_here",
    // .tdlib_path = "/custom/path/libtdjson.so",
    .theme = "md3", // "md3" | "linear" | "flat"
}
```

**Never commit `api_id` / `api_hash`, and never paste them into issues or AI prompts.** The repository's `.gitignore` excludes `*.local.zon`.

Themes and keybinds will be separate files you can edit and reload (planned):

```
~/.config/zigram/themes/*.zon
~/.config/zigram/keybinds.zon
```

## Build and run

```sh
git clone https://github.com/Pivozavr7/ZiGram
cd ZiGram
./scripts/fetch-tdlib.sh      # prebuilt TDLib (tdlib.lock pins the version)
./scripts/fetch-deps.sh       # SDL3 and Dear ImGui sources (sdl.lock, imgui.lock)
./scripts/build-sdl.sh        # builds vendor/sdl/libSDL3.a (needs gcc + cmake)

zig build                 # build core, cli and gui
zig build test            # run tests
zig build run-gui         # launch the GUI (needs Vulkan)
```

Until the login flow lands in the GUI, the headless client exercises the core:

```sh
zig build run-cli -- version
```

## Roadmap

**MVP 0: the core (no GUI)**

- [x] Repo skeleton, build, `fetch-tdlib.sh`, `tdlib.lock`
- [ ] `td.zig`: runtime loading, receiver thread, event queue, request/response matching
- [ ] Authorization: phone, code, 2FA
- [ ] Chat list and message history
- [ ] Send, edit, delete; read marks; file downloads
- [ ] `zigram-cli`: log in, list chats, read and send messages live

**MVP 1: the interface**

- [ ] SDL3 + SDL_GPU + Dear ImGui window, fonts, HiDPI on Wayland
- [ ] Chat list, conversation view with virtual scrolling, input, IME
- [ ] Three themes, configurable keybinds
- [ ] D-Bus notifications, search
- [ ] Media: photos, stickers, voice, video notes, GIFs
- [ ] Multi-chat layout
- [ ] **1.0**: a usable daily client. Packaging (AUR) comes after that.

## Known challenges

Being upfront about the hard parts:

- **Text in immediate-mode UIs is hard.** IME, color emoji and long variable-height message lists need care. RTL scripts are not supported by Dear ImGui.
- **Animated stickers (Lottie/TGS)** are the most expensive feature and come last.
- **Zig moves fast.** The project pins a Zig version and updates deliberately.

## Not affiliated with Telegram

ZiGram is an independent, unofficial client. It is not made, endorsed or supported by Telegram. By using it you agree to follow the [Telegram API Terms of Service](https://core.telegram.org/api/terms). Keep your own `api_id` private and do not use the client for spam or abuse.

## Contributing

The project is very young, so the best contributions right now are **ideas, testing on different setups, and focused PRs for the roadmap items**. Please open an issue before large changes. Read [`AGENTS.md`](AGENTS.md) for the architecture rules and conventions; they apply to human contributors as well.

## License

ZiGram is licensed under the **Apache License 2.0**, see [`LICENSE`](LICENSE).

It uses:

- [TDLib](https://github.com/tdlib/td) (Boost Software License 1.0)
- [Dear ImGui](https://github.com/ocornut/imgui) (MIT)
- [SDL3](https://libsdl.org) (zlib)
