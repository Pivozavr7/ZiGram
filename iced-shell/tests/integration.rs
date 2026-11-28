//! S0 boundary test: start the core, ask TDLib for its version, stop.

use iced_shell::Core;
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// Absolute path of the TDLib shared library inside the repository.
fn tdlib_path() -> String {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let lib = manifest
        .join("../vendor/tdlib/libtdjson.so")
        .canonicalize()
        .expect("vendor/tdlib/libtdjson.so missing; run scripts/fetch-tdlib.sh");
    lib.display().to_string()
}

#[test]
fn version_string_is_reported() {
    assert!(!Core::version().is_empty());
}

#[test]
fn start_query_version_and_stop() {
    let config = format!(r#"{{"tdlib_path":"{}"}}"#, tdlib_path());
    let core = Core::start(&config).expect("core must start");

    let extra = core
        .send(r#"{"@type":"getOption","name":"version"}"#)
        .expect("request must be accepted");

    let deadline = Instant::now() + Duration::from_secs(10);
    let answer: Vec<u8> = loop {
        let event = match core.poll(500).expect("poll must not fail") {
            Some(event) => event,
            None => {
                assert!(Instant::now() < deadline, "no version response within 10s");
                continue;
            }
        };
        if event.extra() == Some(extra) {
            break event.json().to_vec();
        }
        // Spontaneous update: keep polling for the answer.
    };

    let json = std::str::from_utf8(&answer).expect("response is UTF-8");
    assert!(
        json.contains("\"@type\":\"optionValueString\""),
        "unexpected response: {json}"
    );

    // Dropping the core closes the client; a hang or crash fails here.
    drop(core);
}
