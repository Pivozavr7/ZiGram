//! The authorization side of the shell: parsing `updateAuthorizationState`
//! and building the login requests.
//!
//! `setTdlibParameters` is deliberately absent here: it carries the api id
//! and hash, which never leave zig — the shell asks for it through
//! `Core::send_tdlib_parameters`.

use serde::Deserialize;

/// Parsed `authorizationState*` payloads.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(tag = "@type")]
pub enum AuthState {
    #[serde(rename = "authorizationStateWaitTdlibParameters")]
    WaitTdlibParameters,
    #[serde(rename = "authorizationStateWaitPhoneNumber")]
    WaitPhoneNumber,
    #[serde(rename = "authorizationStateWaitCode")]
    WaitCode {
        #[serde(default)]
        is_registered: bool,
    },
    #[serde(rename = "authorizationStateWaitPassword")]
    WaitPassword {
        #[serde(default)]
        password_hint: Option<String>,
    },
    #[serde(rename = "authorizationStateWaitOtherDeviceConfirmation")]
    WaitOtherDeviceConfirmation {
        #[serde(default)]
        link: Option<String>,
    },
    #[serde(rename = "authorizationStateWaitRegistration")]
    WaitRegistration,
    #[serde(rename = "authorizationStateReady")]
    Ready,
    #[serde(rename = "authorizationStateLoggingOut")]
    LoggingOut,
    #[serde(rename = "authorizationStateClosing")]
    Closing,
    #[serde(rename = "authorizationStateClosed")]
    Closed,
    /// Unknown `authorizationState*`: TDLib adds states between versions.
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
struct AuthUpdate<'a> {
    #[serde(rename = "@type")]
    kind: &'a str,
    #[serde(default)]
    authorization_state: Option<AuthState>,
}

/// The authorization state of an event; `None` for anything else.
pub fn parse_auth_state(json: &[u8]) -> Option<AuthState> {
    let update: AuthUpdate = serde_json::from_slice(json).ok()?;
    if update.kind != "updateAuthorizationState" {
        return None;
    }
    update.authorization_state
}

/// `setAuthenticationPhoneNumber`.
pub fn phone_request(phone: &str) -> String {
    serde_json::json!({
        "@type": "setAuthenticationPhoneNumber",
        "phone_number": phone,
    })
    .to_string()
}

/// `checkAuthenticationCode`.
pub fn code_request(code: &str) -> String {
    serde_json::json!({ "@type": "checkAuthenticationCode", "code": code }).to_string()
}

/// `checkAuthenticationPassword`.
pub fn password_request(password: &str) -> String {
    serde_json::json!({
        "@type": "checkAuthenticationPassword",
        "password": password,
    })
    .to_string()
}

/// `requestQrCodeAuthentication`.
pub fn qr_request() -> String {
    serde_json::json!({ "@type": "requestQrCodeAuthentication" }).to_string()
}

/// `resendAuthenticationCode`.
pub fn resend_request() -> String {
    serde_json::json!({ "@type": "resendAuthenticationCode" }).to_string()
}

/// The `message` of an error response, or `None` for anything else.
pub fn error_message(json: &[u8]) -> Option<String> {
    let value: serde_json::Value = serde_json::from_slice(json).ok()?;
    if value["@type"] != "error" {
        return None;
    }
    Some(
        value["message"]
            .as_str()
            .unwrap_or("unknown error")
            .to_string(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wait_code_carries_registration() {
        let state = parse_auth_state(
            br#"{"@type":"updateAuthorizationState","authorization_state":
                {"@type":"authorizationStateWaitCode","is_registered":true}}"#,
        );
        assert_eq!(
            state,
            Some(AuthState::WaitCode {
                is_registered: true
            })
        );
    }

    #[test]
    fn wait_password_carries_the_hint() {
        let state = parse_auth_state(
            br#"{"@type":"updateAuthorizationState","authorization_state":
                {"@type":"authorizationStateWaitPassword","password_hint":"hint"}}"#,
        );
        match state {
            Some(AuthState::WaitPassword { password_hint }) => {
                assert_eq!(password_hint.as_deref(), Some("hint"))
            }
            other => panic!("unexpected state: {other:?}"),
        }
    }

    #[test]
    fn qr_link_is_optional() {
        let state = parse_auth_state(
            br#"{"@type":"updateAuthorizationState","authorization_state":
                {"@type":"authorizationStateWaitOtherDeviceConfirmation"}}"#,
        );
        assert_eq!(
            state,
            Some(AuthState::WaitOtherDeviceConfirmation { link: None })
        );
    }

    #[test]
    fn other_events_are_not_authorization_states() {
        assert_eq!(parse_auth_state(br#"{"@type":"updateOption"}"#), None);
    }

    #[test]
    fn unknown_states_map_to_other() {
        let state = parse_auth_state(
            br#"{"@type":"updateAuthorizationState","authorization_state":
                {"@type":"authorizationStateWaitSomethingNew"}}"#,
        );
        assert_eq!(state, Some(AuthState::Other));
    }

    #[test]
    fn requests_escape_user_text() {
        let request = password_request(r#"pa"ss\w"#);
        let value: serde_json::Value = serde_json::from_str(&request).expect("valid json");
        assert_eq!(value["@type"], "checkAuthenticationPassword");
        assert_eq!(value["password"], r#"pa"ss\w"#);
    }

    #[test]
    fn phone_and_code_requests_carry_their_values() {
        let phone: serde_json::Value =
            serde_json::from_str(&phone_request("+7 999 123-45-67")).expect("valid json");
        assert_eq!(phone["phone_number"], "+7 999 123-45-67");

        let code: serde_json::Value =
            serde_json::from_str(&code_request("12345")).expect("valid json");
        assert_eq!(code["@type"], "checkAuthenticationCode");
        assert_eq!(code["code"], "12345");
    }

    #[test]
    fn qr_and_resend_requests_have_no_fields() {
        let qr: serde_json::Value = serde_json::from_str(&qr_request()).expect("valid json");
        assert_eq!(qr["@type"], "requestQrCodeAuthentication");

        let resend: serde_json::Value =
            serde_json::from_str(&resend_request()).expect("valid json");
        assert_eq!(resend["@type"], "resendAuthenticationCode");
    }

    #[test]
    fn error_responses_yield_their_message() {
        let message =
            error_message(br#"{"@type":"error","code":400,"message":"PHONE_NUMBER_INVALID"}"#);
        assert_eq!(message.as_deref(), Some("PHONE_NUMBER_INVALID"));
        assert_eq!(error_message(br#"{"@type":"ok"}"#), None);
    }
}
