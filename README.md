<div align="center">

<img src="assets/logo.svg" alt="ZiGram logo" width="128" height="128">

# ZiGram

**A fast, native, hackable Telegram client written in Zig.**

Immediate-mode GPU interface · no Electron · no Qt · everything configurable

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg?style=flat-square)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-0.17.x-f7a41d.svg?style=flat-square&logo=zig&logoColor=white)](https://ziglang.org)
[![Platform](https://img.shields.io/badge/platform-Linux-informational.svg?style=flat-square&logo=linux&logoColor=white)](#requirements)
[![TDLib](https://img.shields.io/badge/TDLib-1.8.70-2ea44f.svg?style=flat-square)](https://github.com/tdlib/td)
[![Status](https://img.shields.io/badge/status-pre--alpha-red.svg?style=flat-square)](#status)

[Why](#why-zigram) ·
[Features](#features) ·
[Architecture](#architecture) ·
[Build](#build-and-run) ·
[Configuration](#configuration) ·
[Roadmap](#roadmap) ·
[Contributing](#contributing)

</div>

---

## Status

> [!WARNING]
> **Pre-alpha. ZiGram is not usable as a daily client yet.**
> The login flow (phone, code, 2FA, QR) and a first client view (chat list, message history, sending) are implemented in the GUI. Editing messages, media, themes and everything after it are **planned**. Items in this document are marked as planned until they exist.

The prototype files are split into small single-purpose modules (stage R of the [roadmap](#roadmap) is done); the interface grows from here.

## Why ZiGram

Telegram's official desktop client is excellent, but it is a large Qt/C++ codebase that is hard to modify and slow to build. Other clients are web wrappers. ZiGram takes a different route.

|  |  |
|---|---|
| ⚡ **Native and small** | One Zig binary plus Telegram's own TDLib. No browser engine, no Qt. |
| 🚀 **Fast by construction** | Immediate-mode UI ([Dear ImGui](https://github.com/ocornut/imgui)) rendered through SDL3's GPU API. |
| 🛠️ **Hackable** | Themes, layout and keybinds are plain [`.zon`](https://ziglang.org/) files loaded at runtime. Changing a color does not need a rebuild. |
| 🧩 **Clean separation** | Telegram logic lives in a GUI-free core library with its own headless CLI. The UI is just a client of that core. |
| 🔐 **Honest about the protocol** | ZiGram uses the official, battle-tested TDLib for MTProto, encryption, sync and caching. It does not reimplement them. |

## Features

Everything below is **planned** unless stated otherwise.

| | |
|---|---|
| 🔑 **Login** | Phone number, code, 2FA password, QR login. *Implemented, not yet battle-tested.* |
| 💬 **Chats** | Private chats and groups first; channels, topics and secret chats later. *Chat list, message history and sending work in the GUI.* |
| 🎨 **Three designs** | **MD3** (Material 3), **Linear** (dense, minimal), **Flat** (tdesktop-inspired, refined) |
| 🎛️ **Deep customization** | Colors, rounding, density, fonts and panel widths, all in config files |
| ⌨️ **Keybinds** | tdesktop-compatible defaults, fully remappable, optional vim-style navigation |
| 🪟 **Layouts** | Classic two-pane first, then several chats side by side |
| 🔔 **Notifications** | Native Linux notifications over D-Bus |
| 🌍 **Text** | Cyrillic, CJK, color emoji, IME input |
| 🖼️ **Media** | Photos first, then stickers, voice messages, video notes and GIFs |

Not planned for the first releases: calls, bot UI polish, right-to-left scripts (Dear ImGui does not support them).

<!--
## Screenshots
Add screenshots here once the chat UI exists.
-->

## Architecture

```
┌────────────────────────────────────────────────┐
│  gui/   window and frame loop (thin)           │
├────────────────────────────────────────────────┤
│  ui/    Dear ImGui screens · widgets · themes  │  MVP 1
├────────────────────────────────────────────────┤
│  app/   session · state · commands · config    │  no ImGui, testable
├────────────────────────────────────────────────┤
│  core/  Telegram logic, no GUI imports         │  MVP 0
│         td/     runtime-loaded libtdjson       │
│         auth    authorization state machine    │
│         store/  users · chats · messages       │
├────────────────────────────────────────────────┤
│  libtdjson.so   (official TDLib, JSON API)     │
└────────────────────────────────────────────────┘
```

Dependencies point strictly downward. Design decisions worth knowing:

- **TDLib is loaded at runtime** with `std.DynLib`. There is no C header and no link-time dependency, so ZiGram builds without TDLib present, and you can point it at any compatible `libtdjson.so`.
- **One receiver thread** calls `td_receive` and feeds a queue. The UI thread drains it once per frame with a bounded budget, so a burst of updates never freezes the window.
- **The UI never talks to TDLib directly.** It reads application state and sends commands through the app layer.
- **Small files by rule.** Source files stay short and single-purpose; the limits are enforced by the project's contribution rules.

## Requirements

- **Linux** (developed on Arch; Wayland and X11 through SDL3)
- **Zig 0.17.x** (developed on 0.17.1)
- **SDL3**, **FreeType**, **fontconfig**, **D-Bus** development libraries
- **Vulkan** capable GPU and driver (for the GUI)
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

1. Reads the pinned version and `sha256` from [`tdlib.lock`](tdlib.lock)
2. Fetches the prebuilt library from the [`prebuilt-tdlib`](https://www.npmjs.com/package/prebuilt-tdlib) npm package (statically linked against OpenSSL and zlib)
3. Refuses to continue if the checksum does not match
4. Places the library in `vendor/tdlib/` (git-ignored)

Prefer your own copy? Set `tdlib_path` in the config or `ZIGRAM_TDLIB=/path/to/libtdjson.so`. ZiGram searches, in order: config, environment, `vendor/tdlib/`, `~/.local/share/zigram/`, then system paths. A system package such as the AUR's `telegram-tdlib` works too.

> [!NOTE]
> The prebuilt binary is third-party. Pinning the checksum protects you from silent changes, but if you want full control, build TDLib yourself or use your distro's package.

## Build and run

```sh
git clone https://github.com/Pivozavr7/ZiGram
cd ZiGram

./scripts/fetch-tdlib.sh      # prebuilt TDLib (tdlib.lock pins the version)
./scripts/fetch-deps.sh       # SDL3, Dear ImGui and QR sources (*.lock files)
./scripts/build-sdl.sh        # builds vendor/sdl/libSDL3.a (needs gcc + cmake)

zig build                     # core, cli and gui
zig build test                # unit tests
zig build run-gui             # launch the GUI (needs Vulkan)
zig build run-cli -- version  # headless client
```

## Configuration

ZiGram needs **your own API credentials**. Create an application at [my.telegram.org](https://my.telegram.org), then write `~/.config/zigram/config.zon`:

```zig
.{
    .api_id = 12345,
    .api_hash = "your_api_hash_here",
    // .tdlib_path = "/custom/path/libtdjson.so",
}
```

> [!CAUTION]
> **Never commit `api_id` / `api_hash`, and never paste them into issues or AI prompts.** The repository's `.gitignore` excludes `*.local.zon`.

Themes and keybinds will be separate files you can edit and reload (**planned**):

```
~/.config/zigram/themes/*.zon
~/.config/zigram/keybinds.zon
```

## Roadmap

**Stage R: cleanup** (done)
Split the prototype into small single-purpose modules before the UI grows.

- [x] `store.zig` → `core/store/`
- [x] `gui/main.zig` → `app/` + `ui/`
- [x] `td.zig` → `core/td/` (`search`, `options`, `queue`, `library`, `receiver`, `client`)
- [x] Long 2FA passwords, secret buffers cleared after use
- [x] CI runs tests in the build job

**MVP 0: the core (no GUI)**

- [x] Repo skeleton, build, `fetch-tdlib.sh`, `tdlib.lock`
- [x] Runtime-loaded TDLib, receiver thread, event queue, request/response matching
- [x] Authorization: phone, code, 2FA, QR
- [x] Chat list and message history parsing
- [x] Send a text message
- [ ] Edit, delete, read marks; file downloads
- [ ] `zigram-cli`: log in, list chats, read and send messages live

**MVP 1: the interface** (current)

- [x] SDL3 + SDL_GPU + Dear ImGui window (HiDPI aware)
- [x] Login screen wired to the authorization state machine
- [ ] Theme tokens and `.zon` loader
- [ ] Text check: Cyrillic, CJK, color emoji, IME
- [x] Basic chat list, conversation view and message input
- [ ] Virtual scrolling for long histories
- [ ] Three themes, configurable keybinds
- [ ] D-Bus notifications, search
- [ ] Media: photos, stickers, voice, video notes, GIFs
- [ ] Multi-chat layout
- [ ] **1.0**: a usable daily client. Packaging (AUR) comes after that.

The detailed plan is maintained by the maintainers; the roadmap above tracks the same stages.

## Known challenges

Being upfront about the hard parts:

- **Text in immediate-mode UIs is hard.** IME, color emoji and long variable-height message lists need care. RTL scripts are not supported by Dear ImGui.
- **Animated stickers (Lottie/TGS)** are the most expensive feature and come last.
- **Zig moves fast.** The project pins a Zig version and updates deliberately.

## Contributing

The project is very young, so the most useful contributions right now are **ideas, testing on different setups, and focused PRs for roadmap items**. Please open an issue before large changes. The architecture rules, size limits and conventions apply to human contributors as well; ask the maintainers for the current version.

## Not affiliated with Telegram

ZiGram is an independent, unofficial client. It is not made, endorsed or supported by Telegram. By using it you agree to follow the [Telegram API Terms of Service](https://core.telegram.org/api/terms). Keep your own `api_id` private and do not use the client for spam or abuse.

## License

ZiGram is licensed under the **Apache License 2.0**, see [`LICENSE`](LICENSE).

Built on:

- [TDLib](https://github.com/tdlib/td): Boost Software License 1.0
- [Dear ImGui](https://github.com/ocornut/imgui): MIT
- [SDL3](https://libsdl.org): zlib
- [QR Code generator](https://github.com/nayuki/QR-Code-generator) by Nayuki: MIT
