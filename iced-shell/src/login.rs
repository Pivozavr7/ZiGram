//! The login screen: phone number, code, password and QR states.
//!
//! The panel is drawn from the parsed authorization state; what the user
//! types is sent as plain TDLib requests through `app::Message::Login`.

use iced::widget::qr_code::{self, QRCode};
use iced::widget::{button, column, text, text_input, Column};

use crate::auth::AuthState;

/// Inputs and answer state of the login flow.
pub struct Login {
    pub phone: String,
    pub code: String,
    pub password: String,
    /// Message of the last failed request, shown until the next attempt.
    pub error: Option<String>,
    /// `@extra` of the login request waiting for an answer.
    pub pending: Option<u64>,
    /// Encoded QR matrix and the link it belongs to; the link rotates
    /// about every thirty seconds.
    qr_data: Option<qr_code::Data>,
    qr_link: String,
    /// Set when the user leaves the QR panel for the phone form while
    /// TDLib still reports the QR state.
    back_to_phone: bool,
}

/// What the login screen asks the app to do.
#[derive(Debug, Clone)]
pub enum Message {
    Phone(String),
    Code(String),
    Password(String),
    Submit,
    Qr,
    Resend,
    BackToPhone,
}

impl Login {
    pub fn new() -> Self {
        Login {
            phone: String::new(),
            code: String::new(),
            password: String::new(),
            error: None,
            pending: None,
            qr_data: None,
            qr_link: String::new(),
            back_to_phone: false,
        }
    }

    /// True while the user is filling the phone form that replaced the
    /// QR panel.
    pub fn wants_phone(&self) -> bool {
        self.back_to_phone
    }

    /// Leaves the QR panel for the phone form.
    pub fn go_back_to_phone(&mut self) {
        self.back_to_phone = true;
    }

    /// Drops the local phone override; called when TDLib moves out of
    /// the QR state on its own.
    pub fn leave_back_to_phone(&mut self) {
        self.back_to_phone = false;
    }

    /// Draws the panel of the current authorization state.
    pub fn view(&self, state: &AuthState) -> iced::Element<'_, Message> {
        let mut panel = column![].spacing(8);
        if let Some(error) = &self.error {
            panel = panel.push(text(format!("error: {error}")));
        }
        panel = match state {
            AuthState::WaitPhoneNumber => self.view_phone(panel),
            AuthState::WaitCode { is_registered } => self.view_code(panel, *is_registered),
            AuthState::WaitPassword { password_hint } => {
                self.view_password(panel, password_hint.as_deref())
            }
            AuthState::WaitOtherDeviceConfirmation { link } => {
                if self.back_to_phone {
                    self.view_phone(panel)
                } else {
                    self.view_qr(panel, link)
                }
            }
            AuthState::WaitTdlibParameters | AuthState::Other => panel.push(text("authorizing…")),
            AuthState::WaitRegistration => {
                panel.push(text("registration of new accounts is not supported yet"))
            }
            AuthState::Ready => panel.push(text("authorized")),
            AuthState::LoggingOut | AuthState::Closing | AuthState::Closed => {
                panel.push(text("the session is closing"))
            }
        };
        panel.into()
    }

    /// Remembers the QR link and encodes it for the matrix widget.
    pub fn set_qr_link(&mut self, link: Option<&str>) {
        let link = link.unwrap_or("");
        if self.qr_link == link {
            return;
        }
        self.qr_link = link.to_string();
        self.qr_data = if link.is_empty() {
            None
        } else {
            match qr_code::Data::new(link.as_bytes()) {
                Ok(data) => Some(data),
                Err(err) => {
                    self.error = Some(format!("qr code: {err}"));
                    None
                }
            }
        };
    }

    fn view_phone<'a>(&self, panel: Column<'a, Message>) -> Column<'a, Message> {
        let panel = panel.push(text("Enter your phone number:")).push(
            text_input("Phone", &self.phone)
                .on_input(Message::Phone)
                .on_submit(Message::Submit),
        );
        if self.pending.is_some() {
            return panel.push(text("authorizing…"));
        }
        panel
            .push(button("Sign in").on_press(Message::Submit))
            .push(button("Sign in by QR code").on_press(Message::Qr))
    }

    fn view_code<'a>(
        &self,
        panel: Column<'a, Message>,
        is_registered: bool,
    ) -> Column<'a, Message> {
        let hint = if is_registered {
            "Enter the login code:"
        } else {
            "Enter the signup code:"
        };
        let panel = panel.push(text(hint)).push(
            text_input("Code", &self.code)
                .on_input(Message::Code)
                .on_submit(Message::Submit),
        );
        if self.pending.is_some() {
            return panel.push(text("checking the code…"));
        }
        panel
            .push(button("Continue").on_press(Message::Submit))
            .push(button("Resend code").on_press(Message::Resend))
            .push(button("Sign in by QR code").on_press(Message::Qr))
    }

    fn view_password<'a>(
        &self,
        panel: Column<'a, Message>,
        hint: Option<&str>,
    ) -> Column<'a, Message> {
        let mut panel = panel.push(text("Enter your 2FA password:"));
        if let Some(hint) = hint {
            panel = panel.push(text(format!("hint: {hint}")).size(13));
        }
        panel = panel.push(
            text_input("Password", &self.password)
                .secure(true)
                .on_input(Message::Password)
                .on_submit(Message::Submit),
        );
        if self.pending.is_some() {
            return panel.push(text("checking the password…"));
        }
        panel.push(button("Continue").on_press(Message::Submit))
    }

    fn view_qr<'a>(
        &'a self,
        panel: Column<'a, Message>,
        link: &Option<String>,
    ) -> Column<'a, Message> {
        let panel = panel
            .push(text("Scan this code in Telegram:"))
            .push(text("Settings -> Devices -> Link Desktop Device").size(13));
        if let (Some(data), Some(_)) = (&self.qr_data, link) {
            panel.push(QRCode::new(data))
        } else {
            panel.push(text("waiting for the QR link…"))
        }
        .push(button("Use phone number instead").on_press(Message::BackToPhone))
    }
}
