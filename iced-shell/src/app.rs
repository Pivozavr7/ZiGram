//! Debug window: raw TDLib events as a scrolling list of text lines.

use std::sync::Arc;

use iced::widget::{column, text, Scrollable};
use iced::Task;

use iced_shell::Core;

/// Event lines kept on screen.
const VISIBLE_LINES: usize = 50;

/// Longest event excerpt shown, in bytes.
const MAX_PREVIEW: usize = 160;

/// The whole ui state of the debug shell.
pub struct App {
    core: Arc<Core>,
    events: Vec<String>,
}

/// One TDLib event delivered by the poll thread.
pub enum Message {
    Event { json: Vec<u8>, extra: Option<u64> },
}

impl App {
    pub fn new(core: Arc<Core>) -> Self {
        App {
            core,
            events: Vec::new(),
        }
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        let Message::Event { json, extra } = message;
        let line = preview(&json, extra);
        println!("{line}");
        self.events.push(line);
        if self.events.len() > VISIBLE_LINES {
            self.events.remove(0);
        }
        Task::none()
    }

    pub fn view(&self) -> iced::Element<'_, Message> {
        let mut lines = column![]
            .push(text(format!(
                "zigram {} · core refs {} · {} events",
                Core::version(),
                Arc::strong_count(&self.core),
                self.events.len(),
            )))
            .spacing(2);
        for line in &self.events {
            lines = lines.push(text(line.as_str()).size(13));
        }
        Scrollable::new(lines.padding(12)).into()
    }
}

/// One event as a single printable line: `[extra] json…`.
fn preview(json: &[u8], extra: Option<u64>) -> String {
    let limit = json.len().min(MAX_PREVIEW);
    let body = String::from_utf8_lossy(&json[..limit]);
    match extra {
        Some(value) => format!("[{value}] {body}"),
        None => body.into_owned(),
    }
}
