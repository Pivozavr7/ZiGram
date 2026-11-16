# AGENTS.md: ZiGram

Native Telegram client written in **Zig**, immediate-mode UI (Dear ImGui + SDL3 GPU), on top of **TDLib via its JSON interface** (`libtdjson.so`). Linux only. License: Apache-2.0.

The maintainer speaks Russian: reply to the user in Russian, keep code, comments and commit messages in English.

The roadmap lives in `ZiGram-plan.md`. Pick tasks from there.

## Rule zero: no monoliths

This project has already been hurt by giant files and giant functions (`td.zig` ~900 lines, `gui/main.zig` with a 200-line `main`). Do not repeat that. These rules beat convenience.

**Size limits**

| Thing | Target | Hard limit |
|---|---|---|
| Source file (incl. tests) | <= 300 lines | 500 lines |
| Function | <= 40 lines | 70 lines |
| `main()` in any executable | <= 40 lines | 60 lines |
| Struct with state | <= 10 fields | 15 fields |
| Directory | <= 10 files | split into subdirs |

Hard limit means: do not exceed it, not even "temporarily". If a change would push a file over the limit, **split the file first**, in a separate step, then make the change.

**One responsibility per file.** You must be able to describe a file in one sentence without the word "and". If you cannot, it is two files.

**Check before you write.** Before editing any file run `wc -l` on it. If it is above 300 lines, say so in the plan and prefer adding a new file over growing it.

**Tests** that exceed ~100 lines in a file go to a sibling `<name>_test.zig`, imported from the module root so `zig build test` picks them up.

**Splitting is a refactor, not a feature.** A split commit moves code and fixes imports and nothing else: no renames of behavior, no drive-by fixes, no API redesign. `zig build test` must pass before and after with the same tests.

**`pub` surface stays small.** Make things `pub` only when another file needs them. Each directory has a `root.zig` that re-exports its public API; other code imports the directory, not its inner files.

## Toolchain

- Zig version: **0.17.1**. Do not use APIs from other Zig versions (0.15 and 0.16 examples from training data are outdated: `std.io`, `ArrayList`, writers/readers, `build.zig` and process/IO APIs have all changed). The standard library changes a lot between releases.
- Before writing any Zig, read `.opencode/skill/zig-0-17/SKILL.md`. For style rules also read `.opencode/skill/zig-tiger-style/SKILL.md`.
- APIs this project depends on and that may have moved in 0.17 (verify in stdlib source before use): dynamic library loading (`std.DynLib`), threads and synchronization, `std.json`, file system and `std.Io`, `build.zig` module/executable API.
- Never guess a `std` API. If unsure, read the stdlib source in the installed Zig (`zig env` shows `lib_dir`, look in `std/`) or use `zigdoc` if present. If the code does not compile, fix it from the compiler error, do not rewrite blindly.

## Commands

```
zig build                 # build
zig build test            # run all tests (run after every change)
zig fmt src tests         # format
```

Always run `zig build test` before saying a task is done. Show the user real compiler/test output, never claim it passes without running it.

## Architecture

Dependencies point downward only. Nothing imports upward.

```
src/gui/main.zig      entry point: create window, run frame loop       (thin)
src/ui/               everything drawn on screen                        (MVP 1)
  gfx.zig               Zig wrappers over the C++ shim externs
  gfx_shim.cpp          thin C++ glue to ImGui/SDL, no logic
  theme/                tokens.zig, loader.zig (.zon -> tokens), builtin themes
  widgets/              small reusable pieces: button, avatar, bubble, ...
  screens/              login.zig, chat_list.zig, conversation.zig, ...
src/app/              application layer, no ImGui/SDL
  config.zig            read ~/.config/zigram/config.zon
  log.zig               debug logging with redaction
  session.zig          start core, own the client, drain events per frame
  state.zig             what screens read: current screen, selection, ...
  commands.zig          what screens ask for: send message, open chat, ...
src/core/             Telegram logic, NO GUI imports                    (MVP 0)
  td/                   FFI edge (see below)
  auth/                 authorization state machine
  store/                models and the in-memory store
  updates.zig           parsing of update* objects
  chats.zig, request.zig
src/cli.zig           zigram-cli: headless client for the core
vendor/tdlib/         libtdjson.so (downloaded, gitignored, DO NOT TOUCH)
```

`src/core/td/` is split by responsibility:

```
td/root.zig       re-exports
td/search.zig     library path candidates and search order
td/library.zig    DynLib, symbol table, version check
td/client.zig     Client: send, poll, request/response matching
td/receiver.zig   receiver thread loop
td/queue.zig      thread-safe EventQueue
td/options.zig    option/response parsing helpers
```

`src/core/store/` is split by entity: `user.zig`, `chat.zig`, `message.zig`, `file.zig`, plus `root.zig`. Payload parsing for an entity lives next to that entity, not in one big file.

Rules:
- `core/` must never import `app/`, `ui/`, SDL or ImGui.
- `app/` must never import `ui/`, SDL or ImGui.
- `ui/` reads `app/state` and the store, and sends commands through `app/commands`. It never calls TDLib and never builds TDLib JSON.
- A screen is a small struct with `update` (input to commands) and `draw` (state to pixels). It does not own the client, does not read config files and does not log.
- Auth state -> which screen to show is a pure function in `app/`, covered by tests. Drawing the screen is separate.
- Colors, rounding, spacing and font sizes come from theme tokens. No literal colors or magic sizes in screens or widgets.

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

## UI and frame rules

- The frame loop never blocks. Drain the core event queue once per frame with a bounded budget.
- Long lists use the clipper with a cache of measured item heights.
- Every string shown comes with a length; never rely on null termination for data from TDLib or config.
- Buffers that held a password or login code are zeroed after use.
- Input fields must not silently truncate. If a limit exists, it must be at least what Telegram allows.

## Zig style rules

- Pass `std.mem.Allocator` explicitly. No hidden global allocators.
- Every allocation has a clear owner. Pair with `defer` / `errdefer` immediately.
- Use `std.testing.allocator` in tests so leaks fail the test.
- Explicit error sets for public functions where practical. No `catch unreachable` on I/O, parsing or FFI results.
- Prefer `const`, slices over raw pointers, `comptime T: type` over `anytype` unless truly generic.
- Keep FFI at the edge (`core/td/`). Convert to Zig types immediately.
- Small, focused commits-worth of change. No drive-by refactors.

## Secrets and safety

- `api_id` / `api_hash` live only in `~/.config/zigram/config.zon` (or `*.local.zon`). **Never** put them in the repo, in tests, in logs or in prompts. Never read `.env`, `*.local.zon`, key files.
- Do not edit `vendor/`, `.git/`, `opencode.json`.
- Allowed git: `git status`, `git diff`, `git log`, `git add`, `git commit`, `git push` of the current branch (see "Git and README discipline"). Never run `git push --force` (or `--force-with-lease`), `git reset --hard`, `git rebase`, `git clean`, `git checkout -- <path>`, or anything that rewrites or discards history or work.
- Do not run `rm`, `sudo`, package managers or network tools other than the git push above. Ask the user for anything outside `zig` and the git commands listed.
- Never connect to a real Telegram account in automated tests. Test the parser and state machine on fixed JSON samples.

## Workflow

1. Read `ZiGram-plan.md` and pick **one** small task (one file, one step).
2. Run `wc -l` on every file you plan to touch. If any is above 300 lines, the first step is to split it (see Rule zero).
3. State the plan in 2-4 lines: which files you touch, which new files you create. Then implement.
4. Add or update tests.
5. Run `zig fmt` and `zig build test`.
6. Update `README.md` and `ZiGram-plan.md` when the task finishes a plan item or a whole stage (see below).
7. Commit and push the working state (see below).
8. Report: what changed, what was run, line counts of touched files, the commit hash, what is left. Do not start the next task unasked.

If requirements are unclear, ask one short question instead of inventing behavior.

## Git and README discipline (mandatory)

**A commit and a push for every working state.** A working state is: `zig build` and `zig build test` both pass with real output you have seen. Each such state gets its own commit, pushed right away. Never stack several finished tasks into one commit, and never leave a working state uncommitted at the end of a task.

- Commit only a working state. If the build or tests fail, fix them or report it; do not commit a broken tree.
- One logical change per commit. A split (pure move) and a feature are always separate commits.
- Message format: `type(scope): summary` in English, imperative, under 72 characters. Types: `refactor`, `feat`, `fix`, `test`, `docs`, `build`, `ci`, `chore`. Example: `refactor(core): extract event queue from td.zig`.
- Before every commit run `git status` and `git diff --staged`. Stage files explicitly; do not use `git add -A` blindly. Check that the diff contains no `api_id`, `api_hash`, phone numbers, tokens, `*.local.zon`, or anything under `vendor/`.
- Push with plain `git push` to the current branch only. If the push is rejected or fails, stop, show the error and ask. Do not force, do not rebase, do not switch branches to work around it.
- Do not commit generated output (`.zig-cache/`, `zig-out/`) or downloaded dependencies.

**README must always match reality.** `README.md` is the public face of the project and is updated as part of the work, not afterwards.

- When a task completes a roadmap item, tick it in `README.md` (roadmap) and in `ZiGram-plan.md` **in the same commit** as the final change for that item.
- When a stage finishes (R, MVP 0, each G step of MVP 1), update the README before the stage's last commit: roadmap, the status block, the features table, build/run commands and requirements if they changed. A stage is not done until the README says so.
- Never claim in the README something that does not exist. Planned features stay marked as planned. Do not tick an item that has not been built and tested.
- If a change alters how to build, run or configure the project, update those README sections in the same commit.
- If module layout or size rules change, update `AGENTS.md` and the architecture section of the README together.

## Self-check before reporting done

- Any file over 300 lines? Any function over 40 lines? If yes, say so and propose the split instead of hiding it.
- Did `core/` or `app/` gain an import it must not have?
- Did a screen get TDLib JSON, config or logging code?
- Any literal color or size in `ui/` outside `theme/`?
- Did build and tests pass, and is that exact state committed and pushed? Is the commit hash in my report?
- Did this task finish a plan item or stage, and are `README.md` and `ZiGram-plan.md` updated to say so?
- Does the README claim anything that is not built yet?
