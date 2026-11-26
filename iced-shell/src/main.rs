//! Entry point of the iced debug shell (S1 of the frontend experiment).

mod app;
mod auth;
mod login;
mod poller;

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use app::App;
use iced_shell::Core;

fn main() -> iced::Result {
    let core = Arc::new(start_core());
    // The poll stream is handed to the app exactly once, so a hypothetical
    // second boot can never start a second poll thread.
    let bridge = Arc::new(Mutex::new(Some(poller::start(Arc::clone(&core)))));

    iced::application(
        move || {
            let task = match bridge.lock().unwrap().take() {
                Some(receiver) => iced::Task::stream(receiver),
                None => iced::Task::none(),
            };
            (App::new(Arc::clone(&core)), task)
        },
        App::update,
        App::view,
    )
    .title("ziGram · iced S2 login")
    .window_size((760.0, 520.0))
    .run()
}

/// Starts the core; credentials are read by zig from `config.zon`.
fn start_core() -> Core {
    match Core::start(&start_config()) {
        Ok(core) => core,
        Err(err) => {
            eprintln!("failed to start the zigram core: {err}");
            std::process::exit(1);
        }
    }
}

/// Non-secret startup options: `ZIGRAM_START_CONFIG` (json) merged over
/// the vendored TDLib path, so `database_dir` can point at an empty test
/// database without touching the logged-in session.
fn start_config() -> String {
    let mut options: serde_json::Value = std::env::var("ZIGRAM_START_CONFIG")
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_else(|| serde_json::json!({}));
    if !options
        .get("tdlib_path")
        .is_some_and(|value| !value.is_null())
    {
        if let Some(path) = vendored_tdlib() {
            options["tdlib_path"] = serde_json::Value::String(path);
        }
    }
    options.to_string()
}

/// Absolute path of the vendored TDLib, when it exists.
fn vendored_tdlib() -> Option<String> {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../vendor/tdlib/libtdjson.so")
        .canonicalize()
        .ok()
        .map(|path| path.display().to_string())
}
