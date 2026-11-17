//! Authorization state machine: parsing of `updateAuthorizationState`
//! events (`state.zig`) and builders for the login requests (`requests.zig`).

const state = @import("state.zig");
const requests = @import("requests.zig");

test {
    // Pull the tests of the split-up modules into the `auth` test target.
    _ = state;
    _ = requests;
}

pub const State = state.State;
pub const ParseError = state.ParseError;
pub const Update = state.Update;

pub const RequestError = requests.RequestError;
pub const Parameters = requests.Parameters;
pub const setTdlibParametersRequest = requests.setTdlibParametersRequest;
pub const setAuthenticationPhoneNumberRequest = requests.setAuthenticationPhoneNumberRequest;
pub const checkAuthenticationCodeRequest = requests.checkAuthenticationCodeRequest;
pub const checkAuthenticationPasswordRequest = requests.checkAuthenticationPasswordRequest;
pub const resendAuthenticationCodeRequest = requests.resendAuthenticationCodeRequest;
pub const requestQrCodeAuthenticationRequest = requests.requestQrCodeAuthenticationRequest;
