//! Runtime binding to TDLib's JSON interface (`libtdjson.so`).
//!
//! The implementation lives in the sibling modules of `td/`; this file only
//! re-exports their public API, so `zigram.td.*` keeps working.

const td_client = @import("client.zig");
const td_library = @import("library.zig");
const queue = @import("queue.zig");
const td_options = @import("options.zig");
const receiver = @import("receiver.zig");
const search = @import("search.zig");

test {
    // Pull the tests of the split-up modules into the `td` test target.
    _ = search;
    _ = td_options;
    _ = queue;
    _ = td_library;
    _ = receiver;
    _ = td_client;
}

// Re-exports so `zigram.td.*` keeps working.
pub const Source = search.Source;
pub const Candidate = search.Candidate;
pub const Candidates = search.Candidates;
pub const SearchOptions = search.SearchOptions;
pub const searchCandidatesAlloc = search.searchCandidatesAlloc;
pub const parseOptionString = td_options.parseOptionString;
pub const parseEventExtra = td_options.parseEventExtra;
pub const EventQueue = queue.EventQueue;
pub const Symbols = td_library.Symbols;
pub const InitError = td_library.InitError;
pub const ExecuteError = td_library.ExecuteError;
pub const VersionError = td_library.VersionError;
pub const Library = td_library.Library;
pub const expected_tdlib_version = td_library.expected_tdlib_version;
pub const ClientOptions = td_client.ClientOptions;
pub const ClientInitError = td_client.ClientInitError;
pub const ClientSendError = td_client.ClientSendError;
pub const ClientPollError = td_client.ClientPollError;
pub const Response = td_client.Response;
pub const Client = td_client.Client;
