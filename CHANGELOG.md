# Changelog

Notable changes for each tagged release. The format follows
[Keep a Changelog](https://keepachangelog.com/) loosely; the project is
pre-alpha, so every `0.0.x` tag is a snapshot, not a stable API.

## [0.0.1-alpha] - 2026-11-17

First tagged pre-alpha snapshot: a working vertical slice — login (phone,
code, 2FA, QR), a first client view (chat list, message history, sending
text) in the GUI, and a headless `zigram-cli` on the same core.

### Added

- Core on TDLib's JSON interface: runtime-loaded `libtdjson.so`, receiver
  thread, bounded event queue, request/response matching by `@extra`.
- Authorization state machine with request builders for every login step.
- Chat list and message history parsing; sending text messages.
- GUI: login screens, chat list, conversation view and message input.
- `zigram-cli` headless client.
- CI: test and build jobs, `zig build test` in both.

### Fixed

- Error responses with a string `message` no longer break event parsing.
- Unparsable events are logged and skipped instead of failing the frame.
- Shutdown leaks: configuration strings and library search paths are freed.
- The TDLib client is closed over the protocol (`close` +
  `authorizationStateClosed`), so its background threads no longer outlive
  the static destructors and abort the process on exit.
- The sentinel-terminated project root is freed with the right size.
- Long 2FA passwords fit; password and code buffers are zeroed after use.

### Changed

- Stage R cleanup: the early monoliths are split into single-purpose
  modules — `core/store/`, `core/td/` (`search`, `options`, `queue`,
  `library`, `receiver`, `client`), `core/auth/` (`state`, `requests`),
  and the GUI prototype into `app/` + `ui/` layers.

[0.0.1-alpha]: https://github.com/Pivozavr7/ZiGram/releases/tag/v0.0.1-alpha
