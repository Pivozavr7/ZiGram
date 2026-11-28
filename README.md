<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark_on_dark.svg">
  <img src="assets/wordmark_on_light.svg" alt="ZiGram" width="300">
</picture>

**A fast, native, hackable Telegram client written in Zig.**
No Electron, no Qt. GPU-rendered. Every color is a config file.

<p>
  <a href="#status"><img alt="Status" src="https://img.shields.io/badge/status-pre--alpha-e5484d?labelColor=1f2328"></a>
  <a href="https://ziglang.org"><img alt="Zig" src="https://img.shields.io/badge/zig-0.17.x-f7a41d?logo=zig&logoColor=1f2328&labelColor=1f2328"></a>
  <a href="https://github.com/tdlib/td"><img alt="TDLib" src="https://img.shields.io/badge/tdlib-1.8.70-26a5e4?logo=telegram&logoColor=1f2328&labelColor=1f2328"></a>
  <img alt="Platform" src="https://img.shields.io/badge/linux-wayland%20%7C%20x11-fcc624?logo=linux&logoColor=1f2328&labelColor=1f2328">
  <img alt="Renderer" src="https://img.shields.io/badge/render-vulkan-ac162c?logo=vulkan&logoColor=1f2328&labelColor=1f2328">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-apache--2.0-3b82f6?logo=apache&logoColor=1f2328&labelColor=1f2328"></a>
</p>

[Why](#why) ·
[Features](#features) ·
[Architecture](#architecture) ·
[Build](#build-and-run) ·
[Config](#configuration) ·
[Roadmap](#roadmap) ·
[Changelog](CHANGELOG.md) ·
[Releases](https://github.com/Pivozavr7/ZiGram/releases)

</div>

<a id="status"></a>

> [!WARNING]
> **Pre-alpha. Not usable as a daily client yet.**
> Login (phone, code, 2FA, QR), chat list, message history and sending work in the GUI.
> Everything else is **planned** and marked as such.

## Why

The official desktop client is a huge Qt/C++ codebase that is slow to build and hard to modify. Most alternatives are web wrappers. ZiGram takes a different route:

- **Native and small.** One Zig binary plus TDLib. No browser engine, no Qt.
- **Fast.** Immediate-mode UI ([Dear ImGui](https://github.com/ocornut/imgui)) on SDL3's GPU API.
- **Hackable.** Themes, layout and keybinds are plain [`.zon`](https://ziglang.org/) files read at runtime. Change a color, no rebuild.
- **Clean split.** All Telegram logic lives in a GUI-free core with its own headless CLI. The UI is just a client of it.
- **No homemade crypto.** MTProto, encryption, sync and caching come from the official TDLib.

## Features

| Feature | Details | Status |
|:--|:--|:--|
| Login | Phone, code, 2FA password, QR | ✅ works, not battle-tested |
| Chats | Private chats and groups: list, history, sending | ✅ works |
| Chats (more) | Channels, topics, secret chats | planned |
| Frontends | Dear ImGui by default; an Iced (Rust) frontend behind a small C API | 🚧 experiment |
| Themes | **MD3**, **Linear** (dense, minimal), **Flat** (tdesktop-like) | planned |
| Customization | Colors, rounding, density, fonts, panel widths | planned |
| Keybinds | tdesktop-compatible defaults, remappable, optional vim-style | planned |
| Layouts | Two-pane first, multiple chats side by side later | planned |
| Notifications | Native, over D-Bus | planned |
| Text | Cyrillic, CJK, color emoji, IME | ✅ checked (`--text-test`) |
| Media | Photos, then stickers, voice, video notes, GIFs | planned |

Out of scope for early releases: calls, bot UI polish, right-to-left scripts (Dear ImGui can't render them).

## Architecture

```
┌────────────────────────────────────────────────┐
│ gui/   window and frame loop (thin)            │
├────────────────────────────────────────────────┤
│ ui/    Dear ImGui screens, widgets, themes     │  MVP 1
├────────────────────────────────────────────────┤
│ app/   session, state, commands, config        │  no ImGui, testable
├────────────────────────────────────────────────┤
│ core/  Telegram logic, no GUI imports          │  MVP 0
│        td/    runtime-loaded libtdjson         │
│        auth   authorization state machine      │
│        store/ users, chats, messages           │
├────────────────────────────────────────────────┤
│ libtdjson.so  (official TDLib, JSON API)       │
└────────────────────────────────────────────────┘
```

Dependencies only point down. Key decisions:

- **TDLib is loaded at runtime** via `std.DynLib`. No C header, no link-time dependency; you can point ZiGram at any compatible `libtdjson.so`.
- **One receiver thread** calls `td_receive` and feeds a queue. The UI thread drains it once per frame with a bounded budget, so update bursts can't freeze the window.
- **The UI never talks to TDLib directly.** It reads app state and sends commands through the app layer.
- **Small, single-purpose files.** Size limits are enforced by the contribution rules.

The iced frontend experiment runs beside ImGui, over a small C ABI:

```
┌────────────────────────────────────────────────┐
│ iced-shell/   Rust + iced (experiment)         │
├────────────────────────────────────────────────┤
│ api.zig   C ABI: start · send · poll · free    │  → libzigram_core.a
├────────────────────────────────────────────────┤
│ app/ + core/    the same layers as above       │
└────────────────────────────────────────────────┘
```

- **Rust never sees credentials.** `zigram_start` takes only non-secret JSON options; `api_id`/`api_hash` stay in `config.zon`, read by Zig.
- **Every buffer crossing the boundary is a copy** allocated by Zig and released with `zigram_free(ptr, len)`; no pointer is ever kept on either side.
- The ImGui frontend stays the default until the experiment proves itself (see the roadmap).

## Requirements

- Linux (developed on Arch; Wayland and X11 both work via SDL3)
- Zig 0.17.x (developed on 0.17.1)
- SDL3, FreeType, Fontconfig, D-Bus dev libraries
- Vulkan-capable GPU and driver (GUI only)
- TDLib 1.8.x `libtdjson.so` (no need to compile it, see below)
- Your own `api_id` / `api_hash` from [my.telegram.org](https://my.telegram.org)
- Noto fonts (sans, CJK, color emoji). Without them the GUI falls back to ImGui's default font.
- Rust + Cargo — only for the iced frontend experiment (`iced-shell/`)

Arch:

```sh
sudo pacman -S zig sdl3 freetype2 fontconfig dbus noto-fonts noto-fonts-cjk
```

## Getting TDLib

Building TDLib is slow and memory-hungry, so ZiGram downloads a **prebuilt** `libtdjson.so` and verifies it:

```sh
./scripts/fetch-tdlib.sh
```

The script reads the pinned version and `sha256` from [`tdlib.lock`](tdlib.lock), downloads the library from the [`prebuilt-tdlib`](https://www.npmjs.com/package/prebuilt-tdlib) npm package (statically linked against OpenSSL and zlib), aborts on checksum mismatch, and installs it to `vendor/tdlib/` (git-ignored).

To use your own copy, set `tdlib_path` in the config or `ZIGRAM_TDLIB=/path/to/libtdjson.so`. Lookup order: config → environment → `vendor/tdlib/` → `~/.local/share/zigram/` → system paths. Distro packages such as the AUR's `telegram-tdlib` work too.

> [!NOTE]
> The prebuilt binary is third-party. The checksum protects against silent changes; for full control, build TDLib yourself or use your distro's package.

## Build and run

```sh
git clone https://github.com/Pivozavr7/ZiGram
cd ZiGram

./scripts/fetch-tdlib.sh      # prebuilt TDLib (pinned in tdlib.lock)
./scripts/fetch-deps.sh       # SDL3 and Dear ImGui sources (*.lock files)
./scripts/build-sdl.sh        # builds vendor/sdl/libSDL3.a (needs gcc + cmake)

zig build                     # core, CLI and GUI
zig build test                # unit tests
zig build run-gui             # launch the GUI (needs Vulkan)
zig build run-cli -- version  # headless client
```

**The iced frontend experiment** (this branch) is a separate Cargo project:

```sh
cd iced-shell
cargo run --bin zigram-iced   # same ~/.config/zigram/config.zon
cargo test                    # shell tests
```

To try it without touching your logged-in session, point it at an empty database:

```sh
ZIGRAM_START_CONFIG='{"database_dir":"/tmp/zigram-fresh"}' cargo run --bin zigram-iced
```

**Don't want to build?** Each [release](https://github.com/Pivozavr7/ZiGram/releases) ships a Linux x86_64 tarball with `zigram-gui`, `zigram-cli` and `libtdjson.so`. Extract it and run the binaries from that folder.

## Configuration

Create an application at [my.telegram.org](https://my.telegram.org), then write `~/.config/zigram/config.zon`:

```zig
.{
    .api_id = 12345,
    .api_hash = "your_api_hash_here",
    // .tdlib_path = "/custom/path/libtdjson.so",
}
```

> [!CAUTION]
> Never commit your `api_id` / `api_hash`, and never paste them into issues or AI prompts. `.gitignore` already excludes `*.local.zon`.

Themes and keybinds will be separate editable, reloadable files (**planned**):

```
~/.config/zigram/themes/*.zon
~/.config/zigram/keybinds.zon
```

## Roadmap

| Stage | Progress | |
|:--|:--|:--|
| R: cleanup | ██████████ 5 / 5 | done |
| MVP 0: core | ███████░░░ 5 / 7 | |
| MVP 1: interface | █████░░░░░ 7 / 13 | ← current |

<details>
<summary><b>Stage R: cleanup</b> (done)</summary>

- [x] `store.zig` → `core/store/`
- [x] `gui/main.zig` → `app/` + `ui/`
- [x] `td.zig` → `core/td/` (`search`, `options`, `queue`, `library`, `receiver`, `client`)
- [x] Long 2FA passwords, secret buffers cleared after use
- [x] CI runs tests in the build job

</details>

<details>
<summary><b>MVP 0: core (no GUI)</b></summary>

- [x] Repo skeleton, build, `fetch-tdlib.sh`, `tdlib.lock`
- [x] Runtime-loaded TDLib, receiver thread, event queue, request/response matching
- [x] Authorization: phone, code, 2FA, QR
- [x] Chat list and message history parsing
- [x] Send a text message
- [ ] Edit, delete, read marks, file downloads
- [ ] `zigram-cli`: log in, list chats, read and send messages live

</details>

<details open>
<summary><b>MVP 1: interface</b> (current)</summary>

- [x] SDL3 + SDL_GPU + Dear ImGui window (HiDPI aware)
- [x] Login screen wired to the authorization state machine
- [x] Basic chat list, conversation view and message input
- [x] Chat list in Telegram order with unread counts; chats marked read on open
- [x] Theme tokens and `.zon` loader
- [x] Text check: Cyrillic, CJK, color emoji, IME (`zig build run-gui -- --text-test`)
- [x] Virtual scrolling for long histories
- [ ] Iced frontend: GUI layer moves to Iced (Rust) behind a small C API, core stays Zig (staged experiment: S0 C API + shell, S1 event stream, S2 login screen — all done and accepted; S3 next)
- [ ] Three themes, configurable keybinds
- [ ] D-Bus notifications, search
- [ ] Media: photos, stickers, voice, video notes, GIFs
- [ ] Multi-chat layout
- [ ] **1.0**: a client you can use every day. AUR packaging follows.

</details>

## Known challenges

- **Text in immediate-mode UIs is hard.** IME, color emoji and long variable-height lists need care. RTL is unsupported by Dear ImGui.
- **Animated stickers (Lottie/TGS)** are the most expensive feature, so they come last.
- **Zig moves fast.** The project pins a Zig version and upgrades deliberately.

## Contributing

The most useful help right now: ideas, testing on different setups, and focused PRs for roadmap items. Open an issue before anything big. Architecture rules and size limits apply to everyone; ask the maintainers for the current version.

## Disclaimer

ZiGram is an independent, unofficial client, not made, endorsed or supported by Telegram. By using it you agree to the [Telegram API Terms of Service](https://core.telegram.org/api/terms). Keep your `api_id` private and don't use the client for spam or abuse.

## License

Apache License 2.0, see [`LICENSE`](LICENSE).

Built on:

| Project | License | Used for |
|:--|:--|:--|
| [TDLib](https://github.com/tdlib/td) | BSL-1.0 | Telegram protocol |
| [Dear ImGui](https://github.com/ocornut/imgui) | MIT | UI |
| [SDL3](https://libsdl.org) | zlib | Window, input, GPU |
| [QR Code generator](https://github.com/nayuki/QR-Code-generator) by Nayuki | MIT | QR encoder, ported to Zig |

<div align="center">
<sub><a href="#">Back to top</a></sub>
</div>
