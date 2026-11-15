# AGENTS.md: ZiGram

Native Telegram client written in **Zig**, immediate-mode UI (Dear ImGui + SDL3 GPU), on top of **TDLib via its JSON interface** (`libtdjson.so`). Linux only. License: Apache-2.0.

The maintainer speaks Russian: reply to the user in Russian, keep code, comments and commit messages in English.

## Toolchain

- Zig version: **0.17.1**. Do not use APIs from other Zig versions (0.15 and 0.16 examples from training data are outdated: `std.io`, `ArrayList`, writers/readers, `build.zig` and process/IO APIs have all changed). The standard library changes a lot between releases.
- Before writing any Zig, read `.opencode/skill/zig-0-17/SKILL.md`. For style rules also read `.opencode/skill/zig-tiger-style/SKILL.md`.
- APIs this project depends on and that may have moved in 0.17 (verify in stdlib source before use): dynamic library loading (`std.DynLib`), threads and synchronization, `std.json`, file system and `std.Io`, `build.zig` module/executable API.
- Never guess a `std` API. If unsure, read the stdlib source in the installed Zig (`zig env` shows `lib_dir`, look in `std/`) or use `zigdoc` if present. If the code does not compile, fix it from the compiler error, do not rewrite blindly.
- Installed skills: `zig-0-17` (API guidance for the version above) and `zig-tiger-style` (general style). Do not load skills for other Zig versions.

## Commands

```
zig build                 # build
zig build test            # run all tests (run after every change)
zig fmt src tests         # format
```

Always run `zig build test` before saying a task is done. Show the user real compiler/test output, never claim it passes without running it.

## Architecture

```
src/core/   Telegram logic, NO GUI imports       (MVP 0)
  td.zig        DynLib loader + extern fn table for libtdjson
  auth.zig      authorization state machine
  store.zig     models: User, Chat, Message, File
  updates.zig   parsing of update* objects
src/app/    application state, event queue
src/ui/     Dear ImGui screens, themes, widgets   (MVP 1)
src/cli.zig zigram-cli: headless test client for core
vendor/tdlib/  libtdjson.so (downloaded, gitignored, DO NOT TOUCH)
```

Rules:
- `core/` must never import UI, SDL or ImGui.
- UI only reads `store` and sends commands. It never calls TDLib directly.

## TDLib rules (important)

- Library is loaded at runtime with `std.DynLib`. No header, no `@cImport` for TDLib. Needed symbols: `td_create_client_id`, `td_send`, `td_receive`, `td_execute`.
- Search order for the library: config `tdlib_path`, env `ZIGRAM_TDLIB`, `vendor/tdlib/`, `~/.local/share/zigram/`, system.
- `td_receive` blocks: call it **only from one dedicated thread**. Strings it returns are valid only until the next `td_receive` call in that thread, so **copy before handing off**.
- `td_execute` result is valid only until the next `td_execute` call in the same thread. Copy it.
- `td_send` may be called from any thread.
- Every request gets an `@extra` value; match responses to requests by it.
- Parse JSON tolerantly: ignore unknown fields (`ignore_unknown_fields = true`). TDLib adds fields between versions.
- Pinned TDLib version: **1.8.70**. Check at startup via `getOption` / `version` and warn on mismatch.
- Never log message text or phone numbers at normal log levels.

## Zig style rules

- Pass `std.mem.Allocator` explicitly. No hidden global allocators.
- Every allocation has a clear owner. Pair with `defer` / `errdefer` immediately.
- Use `std.testing.allocator` in tests so leaks fail the test.
- Explicit error sets for public functions where practical. No `catch unreachable` on I/O, parsing or FFI results.
- Prefer `const`, slices over raw pointers, `comptime T: type` over `anytype` unless truly generic.
- Keep FFI at the edge (`td.zig`). Convert to Zig types immediately.
- Small, focused commits-worth of change. No drive-by refactors.

## Secrets and safety

- `api_id` / `api_hash` live only in `~/.config/zigram/config.zon` (or `*.local.zon`). **Never** put them in the repo, in tests, in logs or in prompts. Never read `.env`, `*.local.zon`, key files.
- Do not edit `vendor/`, `.git/`, `opencode.json`.
- Do not run `git push`, `git reset`, `rm`, `sudo`, package managers or network tools. Ask the user for anything outside `zig` and read-only `git`.
- Never connect to a real Telegram account in automated tests. Test the parser and state machine on fixed JSON samples.

## Workflow

1. Read the roadmap below and pick **one** small task (one file, one step).
2. State the plan in 2-4 lines, then implement.
3. Add or update tests.
4. Run `zig fmt` and `zig build test`.
5. Report: what changed, what was run, what is left. Do not start the next task unasked.

If requirements are unclear, ask one short question instead of inventing behavior.

## Roadmap (MVP 0 = core, MVP 1 = UI)

- [ ] 0.0 skeleton: `build.zig`, `build.zig.zon`, `scripts/fetch-tdlib.sh`, `tdlib.lock`
- [ ] 0.1 `td.zig`: DynLib, symbols, version check, receiver thread, event queue, `@extra` matching
- [ ] 0.2 `auth.zig`: WaitTdlibParameters, WaitPhoneNumber, WaitCode, WaitPassword, Ready; `zigram-cli login`
- [ ] 0.3 chats list and history (`loadChats`, `getChatHistory`, updates)
- [ ] 0.4 send/edit/delete, read marks, file download, tests
- [ ] 0.5+ UI (SDL3 + SDL_GPU + ImGui), themes (MD3, Linear, Flat), hotkeys, D-Bus notifications, media

Definition of done for MVP 0: `zigram-cli` logs in, lists chats, reads history, sends and receives messages live.

## UI notes (for MVP 1)

- Dear ImGui text weaknesses: IME, color emoji, RTL. Load Cyrillic/CJK/emoji fonts via fallback chain; RTL is not supported by ImGui, do not promise it.
- Message list needs virtual scrolling (ImGui clipper) with variable row height.
- Themes and keybinds are plain `.zon` files loaded at runtime.
