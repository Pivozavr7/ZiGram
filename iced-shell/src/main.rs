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
    .title("ziGram · iced S1 debug")
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

/// Non-secret startup options: point the core at the vendored TDLib.
fn start_config() -> String {
    let tdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../vendor/tdlib/libtdjson.so");
    match tdlib.canonicalize() {
        Ok(path) => format!(r#"{{"tdlib_path":"{}"}}"#, path.display()),
        Err(_) => "{}".to_string(),
    }
}
