//! The shell state: the login panel on top, raw TDLib events below.

use std::collections::VecDeque;
use std::sync::Arc;
use std::time::Duration;

use iced::widget::{column, text, Scrollable};
use iced::Task;

use crate::auth::{self, AuthState};
use crate::login::{self, Login};
use iced_shell::Core;

/// Event lines kept on screen.
const VISIBLE_LINES: usize = 50;

/// Longest event excerpt shown, in bytes.
const MAX_PREVIEW: usize = 160;

/// How long a login request may stay unanswered before the ui gives up.
const PENDING_TIMEOUT: Duration = Duration::from_secs(15);

/// The whole ui state of the debug shell.
pub struct App {
    core: Arc<Core>,
    events: VecDeque<String>,
    /// Last parsed `updateAuthorizationState`.
    auth: Option<AuthState>,
    /// Set once the credentials have been sent to TDLib.
    tdlib_sent: bool,
    login: Login,
}

/// What the window asks the app to do.
#[derive(Debug, Clone)]
pub enum Message {
    Event {
        json: Vec<u8>,
        extra: Option<u64>,
    },
    Login(login::Message),
    /// The login request `extra` got no answer in time.
    Timeout {
        extra: u64,
    },
}

impl App {
    pub fn new(core: Arc<Core>) -> Self {
        App {
            core,
            events: VecDeque::new(),
            auth: None,
            tdlib_sent: false,
            login: Login::new(),
        }
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Event { json, extra } => {
                self.on_event(json, extra);
                Task::none()
            }
            Message::Login(login_message) => self.on_login(login_message),
            Message::Timeout { extra } => {
                self.on_timeout(extra);
                Task::none()
            }
        }
    }

    /// Fails the request that went silent; a late answer is then
    /// ignored by the `@extra` check for free.
    fn on_timeout(&mut self, extra: u64) {
        if self.login.pending == Some(extra) {
            self.login.pending = None;
            self.login.error = Some("no answer from the core".into());
        }
    }

    /// One event from the poll thread: log it, apply authorization
    /// changes, settle the login request waiting for this answer.
    fn on_event(&mut self, json: Vec<u8>, extra: Option<u64>) {
        let line = preview(&json, extra);
        println!("{line}");
        self.events.push_back(line);
        if self.events.len() > VISIBLE_LINES {
            self.events.pop_front();
        }
        if let Some(state) = auth::parse_auth_state(&json) {
            self.on_auth_state(state);
        }
        if let (Some(extra), Some(pending)) = (extra, self.login.pending) {
            if extra == pending {
                self.login.pending = None;
                self.login.error = auth::error_message(&json);
            }
        }
    }

    /// Applies a new authorization state: the core needs its parameters
    /// once, before it can ask for a phone number.
    fn on_auth_state(&mut self, state: AuthState) {
        if state == AuthState::WaitTdlibParameters && !self.tdlib_sent {
            self.tdlib_sent = true;
            if let Err(err) = self.core.send_tdlib_parameters() {
                let line = format!("setTdlibParameters failed: {err}");
                println!("{line}");
                self.events.push_back(line);
            }
        }
        // An error from the previous step says nothing about the new one.
        if self.auth.as_ref() != Some(&state) {
            self.login.error = None;
        }
        // The phone override only makes sense while TDLib reports QR.
        if !matches!(state, AuthState::WaitOtherDeviceConfirmation { .. }) {
            self.login.leave_back_to_phone();
        }
        match state {
            AuthState::WaitCode { .. } => self.login.code.clear(),
            AuthState::WaitPassword { .. } => self.login.password.clear(),
            AuthState::WaitOtherDeviceConfirmation { ref link } => {
                self.login.set_qr_link(link.as_deref())
            }
            _ => {}
        }
        self.auth = Some(state);
    }

    /// Turns a login message into a request to the core.
    fn on_login(&mut self, message: login::Message) -> Task<Message> {
        match message {
            login::Message::Phone(value) => {
                self.login.phone = value;
                Task::none()
            }
            login::Message::Code(value) => {
                self.login.code = value;
                Task::none()
            }
            login::Message::Password(value) => {
                self.login.password = value;
                Task::none()
            }
            login::Message::Submit => self.submit(),
            login::Message::Qr => {
                self.login.leave_back_to_phone();
                self.send_login(auth::qr_request())
            }
            login::Message::Resend => self.send_login(auth::resend_request()),
            login::Message::BackToPhone => self.back_to_phone(),
            login::Message::Cancel => {
                self.login.pending = None;
                Task::none()
            }
        }
    }

    /// Leaves the QR panel for the phone form. With a remembered number
    /// the core is told right away; TDLib then moves back to the code
    /// state on its own.
    fn back_to_phone(&mut self) -> Task<Message> {
        self.login.go_back_to_phone();
        if !self.login.phone.is_empty() {
            return self.send_login(auth::phone_request(&self.login.phone));
        }
        Task::none()
    }

    /// Sends the request that belongs to the current state and input.
    fn submit(&mut self) -> Task<Message> {
        if self.login.wants_phone() {
            if !self.login.phone.is_empty() {
                return self.send_login(auth::phone_request(&self.login.phone));
            }
            return Task::none();
        }
        let request = match &self.auth {
            Some(AuthState::WaitPhoneNumber) if !self.login.phone.is_empty() => {
                auth::phone_request(&self.login.phone)
            }
            Some(AuthState::WaitCode { .. }) if !self.login.code.is_empty() => {
                auth::code_request(&self.login.code)
            }
            Some(AuthState::WaitPassword { .. }) if !self.login.password.is_empty() => {
                auth::password_request(&self.login.password)
            }
            _ => return Task::none(),
        };
        self.send_login(request)
    }

    /// Sends one login request, remembers it until the answer arrives
    /// and arms a timeout in case the answer never comes.
    fn send_login(&mut self, request: String) -> Task<Message> {
        if self.login.pending.is_some() {
            self.login.error = Some("waiting for the previous request".into());
            return Task::none();
        }
        match self.core.send(&request) {
            Ok(extra) => {
                self.login.pending = Some(extra);
                self.login.error = None;
                timeout_task(extra)
            }
            Err(err) => {
                self.login.error = Some(err.to_string());
                Task::none()
            }
        }
    }

    pub fn view(&self) -> iced::Element<'_, Message> {
        let auth = match &self.auth {
            Some(state) => format!("{state:?}"),
            None => "waiting for the core".to_string(),
        };
        let mut root = column![]
            .push(text(format!(
                "zigram {} · {auth} · core refs {} · {} events",
                Core::version(),
                Arc::strong_count(&self.core),
                self.events.len(),
            )))
            .spacing(6)
            .padding(12);
        if let Some(state) = &self.auth {
            root = root.push(self.login.view(state).map(Message::Login));
        }
        let mut lines = column![].spacing(2);
        for line in &self.events {
            lines = lines.push(text(line.as_str()).size(13));
        }
        root = root.push(Scrollable::new(lines).height(iced::Fill));
        root.into()
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

/// Fails the request `extra` when no answer arrives in time. The sleep
/// lives on its own thread, so the ui executor stays free; a cancelled
/// request just ignores the late tick.
fn timeout_task(extra: u64) -> Task<Message> {
    let (tx, rx) = iced::futures::channel::oneshot::channel();
    std::thread::spawn(move || {
        std::thread::sleep(PENDING_TIMEOUT);
        let _ = tx.send(());
    });
    Task::future(async move {
        let _ = rx.await;
        Message::Timeout { extra }
    })
}
