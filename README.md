<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark_on_dark.svg">
  <img src="assets/wordmark_on_light.svg" alt="ziGram logo" width="300">
</picture>

# zigram

### a fast, native, hackable telegram client written in zig

no electron &nbsp;·&nbsp; no qt &nbsp;·&nbsp; gpu-rendered &nbsp;·&nbsp; every color is a config file &nbsp;·&nbsp; holy vibecode

<br>

<a href="#status"><img src="https://img.shields.io/badge/status-pre--alpha-e5484d?style=for-the-badge" alt="status"></a>
<a href="https://ziglang.org"><img src="https://img.shields.io/badge/zig-0.17.x-f7a41d?style=for-the-badge&logo=zig&logoColor=black" alt="zig"></a>
<a href="https://github.com/tdlib/td"><img src="https://img.shields.io/badge/tdlib-1.8.70-26a5e4?style=for-the-badge&logo=telegram&logoColor=white" alt="tdlib"></a>
<a href="#requirements"><img src="https://img.shields.io/badge/linux-wayland%20%2B%20x11-1f2328?style=for-the-badge&logo=linux&logoColor=white" alt="linux"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-apache--2.0-3b82f6?style=for-the-badge&logo=apache&logoColor=white" alt="license"></a>

<br>

<img src="https://img.shields.io/badge/ui-dear%20imgui-4296fa?style=flat-square" alt="dear imgui">
<img src="https://img.shields.io/badge/window-sdl3%20gpu-8b5cf6?style=flat-square" alt="sdl3">
<img src="https://img.shields.io/badge/render-vulkan-ac162c?style=flat-square&logo=vulkan&logoColor=white" alt="vulkan">
<img src="https://img.shields.io/badge/protocol-mtproto%20via%20tdlib-2ea44f?style=flat-square" alt="mtproto">
<img src="https://img.shields.io/badge/config-.zon-f7a41d?style=flat-square" alt="zon config">

<br><br>

[**why**](#why-zigram) &nbsp;·&nbsp;
[**features**](#features) &nbsp;·&nbsp;
[**architecture**](#architecture) &nbsp;·&nbsp;
[**build**](#build-and-run) &nbsp;·&nbsp;
[**config**](#configuration) &nbsp;·&nbsp;
[**roadmap**](#roadmap) &nbsp;·&nbsp;
[**changelog**](CHANGELOG.md) &nbsp;·&nbsp;
[**releases**](https://github.com/Pivozavr7/ZiGram/releases)

</div>

<br>

> [!WARNING]
> **pre-alpha. you can't use this as your daily client yet.**
>
> login (phone, code, 2fa, qr) works in the gui, and so does a first client view: chat list, message history, sending. editing, media, themes and everything after that are still **planned**. anything in this readme is marked "planned" until it actually exists.

<br>

## why zigram

telegram's official desktop client is great, but it's a huge qt/c++ codebase that's painful to modify and slow to build. most other clients are web wrappers in a trench coat. zigram goes another way:

| | |
|:--|:--|
| ⚡ **native and small** | one zig binary plus telegram's own tdlib. no browser engine, no qt. |
| 🚀 **fast by construction** | immediate-mode ui ([dear imgui](https://github.com/ocornut/imgui)) drawn through sdl3's gpu api. |
| 🛠️ **hackable** | themes, layout and keybinds are plain [`.zon`](https://ziglang.org/) files read at runtime. change a color, no rebuild. |
| 🧩 **clean split** | all telegram logic lives in a gui-free core with its own headless cli. the ui is just a client of that core. |
| 🔐 **no crypto cosplay** | mtproto, encryption, sync and caching come from the official, battle-tested tdlib. zigram doesn't reimplement any of it. |

<br>

## features

everything here is **planned** unless it says otherwise.

| | | |
|:--|:--|:--|
| 🔑 **login** | phone, code, 2fa password, qr | `works`, not battle-tested yet |
| 💬 **chats** | private chats and groups first, then channels, topics, secret chats | `works`: list, history, sending |
| 🎨 **three designs** | **md3** (material 3), **linear** (dense, minimal), **flat** (tdesktop-inspired) | `planned` |
| 🎛️ **deep customization** | colors, rounding, density, fonts, panel widths, all in config files | `planned` |
| ⌨️ **keybinds** | tdesktop-compatible defaults, fully remappable, optional vim-style navigation | `planned` |
| 🪟 **layouts** | classic two-pane first, later several chats side by side | `planned` |
| 🔔 **notifications** | native linux notifications over d-bus | `planned` |
| 🌍 **text** | cyrillic, cjk, color emoji, ime input | `planned` |
| 🖼️ **media** | photos first, then stickers, voice, video notes, gifs | `planned` |

not planned for the first releases: calls, bot ui polish, right-to-left scripts (dear imgui can't do them).

<!--
## screenshots
add screenshots here once the chat ui exists.
-->

<br>

## architecture

```
┌────────────────────────────────────────────────┐
│  gui/   window and frame loop (thin)           │
├────────────────────────────────────────────────┤
│  ui/    dear imgui screens · widgets · themes  │  mvp 1
├────────────────────────────────────────────────┤
│  app/   session · state · commands · config    │  no imgui, testable
├────────────────────────────────────────────────┤
│  core/  telegram logic, no gui imports         │  mvp 0
│         td/     runtime-loaded libtdjson       │
│         auth    authorization state machine    │
│         store/  users · chats · messages       │
├────────────────────────────────────────────────┤
│  libtdjson.so   (official tdlib, json api)     │
└────────────────────────────────────────────────┘
```

dependencies only point down. a few decisions worth knowing about:

- **tdlib is loaded at runtime** with `std.DynLib`. no c header, no link-time dependency. zigram builds without tdlib present, and you can point it at any compatible `libtdjson.so`.
- **one receiver thread** calls `td_receive` and feeds a queue. the ui thread drains it once per frame with a bounded budget, so a burst of updates can't freeze the window.
- **the ui never talks to tdlib directly.** it reads app state and sends commands through the app layer.
- **small files, by rule.** source files stay short and single-purpose. the limits are enforced by the project's contribution rules.

<br>

## requirements

- **linux**: developed on arch, wayland and x11 both work through sdl3
- **zig 0.17.x**: developed on 0.17.1
- **sdl3**, **freetype**, **fontconfig**, **d-bus** dev libraries
- a **vulkan** capable gpu and driver (for the gui)
- **tdlib 1.8.x** `libtdjson.so`. you don't have to compile it, see the next section
- your own telegram **`api_id` / `api_hash`** from [my.telegram.org](https://my.telegram.org)
- **noto fonts** (sans, cjk, color emoji): the gui renders text with system fonts and falls back to imgui's default when they are missing

on arch:

```sh
sudo pacman -S zig sdl3 freetype2 fontconfig dbus noto-fonts noto-fonts-cjk
```

<br>

## getting tdlib without compiling it

building tdlib takes forever and eats a lot of ram, so zigram skips that. the repo ships a small script that downloads a **prebuilt** `libtdjson.so` and checks it against a pinned checksum:

```sh
./scripts/fetch-tdlib.sh
```

1. reads the pinned version and `sha256` from [`tdlib.lock`](tdlib.lock)
2. grabs the prebuilt library from the [`prebuilt-tdlib`](https://www.npmjs.com/package/prebuilt-tdlib) npm package (statically linked against openssl and zlib)
3. stops if the checksum doesn't match
4. puts the library in `vendor/tdlib/` (git-ignored)

prefer your own copy? set `tdlib_path` in the config, or `ZIGRAM_TDLIB=/path/to/libtdjson.so`. zigram looks in this order: config, environment, `vendor/tdlib/`, `~/.local/share/zigram/`, then system paths. a system package like the aur's `telegram-tdlib` works too.

> [!NOTE]
> the prebuilt binary is third-party. the pinned checksum protects you from silent changes, but if you want full control, build tdlib yourself or use your distro's package.

<br>

## build and run

```sh
git clone https://github.com/Pivozavr7/ZiGram
cd ZiGram

./scripts/fetch-tdlib.sh      # prebuilt tdlib (tdlib.lock pins the version)
./scripts/fetch-deps.sh       # sdl3 and dear imgui sources (*.lock files)
./scripts/build-sdl.sh        # builds vendor/sdl/libSDL3.a (needs gcc + cmake)

zig build                     # core, cli and gui
zig build test                # unit tests
zig build run-gui             # launch the gui (needs vulkan)
zig build run-cli -- version  # headless client
```

**don't want to compile anything?** every [release](https://github.com/Pivozavr7/ZiGram/releases) has a linux x86_64 tarball with `zigram-gui`, `zigram-cli` and `libtdjson.so`. extract it and run the binaries from that folder. what changed in each release lives in [CHANGELOG.md](CHANGELOG.md).

<br>

## configuration

zigram needs **your own api credentials**. create an application at [my.telegram.org](https://my.telegram.org), then write `~/.config/zigram/config.zon`:

```zig
.{
    .api_id = 12345,
    .api_hash = "your_api_hash_here",
    // .tdlib_path = "/custom/path/libtdjson.so",
}
```

> [!CAUTION]
> **never commit your `api_id` / `api_hash`, and never paste them into issues or ai prompts.** the repo's `.gitignore` already excludes `*.local.zon`.

themes and keybinds will be separate files you can edit and reload (**planned**):

```
~/.config/zigram/themes/*.zon
~/.config/zigram/keybinds.zon
```

<br>

## roadmap

```
stage r   cleanup        ██████████  5 / 5
mvp 0     the core       ███████░░░  5 / 7
mvp 1     the interface  ███░░░░░░░  3 / 11   ← we are here
```

<details open>
<summary><b>stage r: cleanup</b> &nbsp;<code>done</code></summary>

<br>

split the prototype into small single-purpose modules before the ui grows.

- [x] `store.zig` → `core/store/`
- [x] `gui/main.zig` → `app/` + `ui/`
- [x] `td.zig` → `core/td/` (`search`, `options`, `queue`, `library`, `receiver`, `client`)
- [x] long 2fa passwords, secret buffers cleared after use
- [x] ci runs tests in the build job

</details>

<details open>
<summary><b>mvp 0: the core (no gui)</b></summary>

<br>

- [x] repo skeleton, build, `fetch-tdlib.sh`, `tdlib.lock`
- [x] runtime-loaded tdlib, receiver thread, event queue, request/response matching
- [x] authorization: phone, code, 2fa, qr
- [x] chat list and message history parsing
- [x] send a text message
- [ ] edit, delete, read marks, file downloads
- [ ] `zigram-cli`: log in, list chats, read and send messages live

</details>

<details open>
<summary><b>mvp 1: the interface</b> &nbsp;<code>current</code></summary>

<br>

- [x] sdl3 + sdl_gpu + dear imgui window (hidpi aware)
- [x] login screen wired to the authorization state machine
- [x] basic chat list, conversation view and message input
- [x] chat list sorted by telegram order with unread counts, chats marked read on open
- [x] theme tokens and `.zon` loader
- [x] text check: cyrillic, cjk, color emoji, ime (`zig build run-gui -- --text-test`)
- [ ] virtual scrolling for long histories
- [ ] three themes, configurable keybinds
- [ ] d-bus notifications, search
- [ ] media: photos, stickers, voice, video notes, gifs
- [ ] multi-chat layout
- [ ] **1.0**: a client you can actually use every day. aur packaging comes after that.

</details>

the detailed plan is kept by the maintainers. the roadmap above tracks the same stages.

<br>

## known challenges

the hard parts, up front:

- **text in immediate-mode uis is hard.** ime, color emoji and long variable-height message lists all need care. rtl scripts aren't supported by dear imgui at all.
- **animated stickers (lottie/tgs)** are the most expensive feature, so they come last.
- **zig moves fast.** the project pins a zig version and upgrades on purpose, not by accident.

<br>

## logo

the orange tile with the lightning-z, the icon and the long wordmark, live in `assets/`:

<img src="assets/icon_orange.svg" alt="ziGram icon" width="80" height="80">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark_on_dark.svg">
  <img src="assets/wordmark_on_light.svg" alt="ziGram wordmark" width="280">
</picture>

<br>

## contributing

the project is very young, so the most useful things right now are **ideas, testing on different setups, and focused prs for roadmap items**. open an issue before anything big. the architecture rules, size limits and conventions apply to humans too, ask the maintainers for the current version.

<br>

## not affiliated with telegram

zigram is an independent, unofficial client. telegram doesn't make, endorse or support it. by using it you agree to the [telegram api terms of service](https://core.telegram.org/api/terms). keep your `api_id` private and don't use the client for spam or abuse.

<br>

## license

apache license 2.0, see [`LICENSE`](LICENSE).

standing on the shoulders of:

| | | |
|:--|:--|:--|
| [tdlib](https://github.com/tdlib/td) | boost software license 1.0 | telegram protocol |
| [dear imgui](https://github.com/ocornut/imgui) | mit | ui |
| [sdl3](https://libsdl.org) | zlib | window, input, gpu |
| [qr code generator](https://github.com/nayuki/QR-Code-generator) by nayuki | mit | qr encoder, ported to zig |

<br>

<div align="center">

<sub>made with zig and too much coffee · [back to top](#zigram)</sub>

</div>
