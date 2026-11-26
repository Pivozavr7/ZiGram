//! Safe wrappers over the zigram C ABI.
//!
//! Contract: `poll` may run on one thread at a time; `Drop` stops the core,
//! so every thread that calls into a `Core` must be joined before the last
//! handle is dropped.

mod ffi;

use std::ffi::{CStr, CString};
use std::os::raw::c_void;
use std::slice;

/// A running ZiGram core behind an opaque handle.
#[derive(Debug)]
pub struct Core {
    handle: *mut c_void,
}

// The C API is thread safe by design (`zigram_send` may run anywhere,
// `zigram_poll_event` from one thread at a time); stopping is the owner's
// job after the other threads are joined.
unsafe impl Send for Core {}
unsafe impl Sync for Core {}

/// Why a C API call failed.
#[derive(Debug, PartialEq)]
pub enum Error {
    /// The string contained an interior NUL byte.
    InteriorNul(std::ffi::NulError),
    /// `zigram_start` returned null.
    StartFailed,
    /// `zigram_send` assigned no `@extra`.
    SendFailed,
    /// `zigram_poll_event` reported an error.
    PollFailed,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::InteriorNul(err) => write!(f, "interior NUL in string: {err}"),
            Error::StartFailed => write!(f, "core failed to start"),
            Error::SendFailed => write!(f, "core rejected the request"),
            Error::PollFailed => write!(f, "core failed to poll events"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::ffi::NulError> for Error {
    fn from(err: std::ffi::NulError) -> Self {
        Error::InteriorNul(err)
    }
}

impl Core {
    /// Starts the core; `config_json` carries non-secret options and may be
    /// `"{}"`. Credentials are read by zig from `config.zon`.
    pub fn start(config_json: &str) -> Result<Core, Error> {
        let json = CString::new(config_json)?;
        let handle = unsafe { ffi::zigram_start(json.as_ptr()) };
        if handle.is_null() {
            return Err(Error::StartFailed);
        }
        Ok(Core { handle })
    }

    /// Sends one request and returns the `@extra` assigned by the core.
    pub fn send(&self, request: &str) -> Result<u64, Error> {
        let json = CString::new(request)?;
        let extra = unsafe { ffi::zigram_send(self.handle, json.as_ptr()) };
        if extra == 0 {
            return Err(Error::SendFailed);
        }
        Ok(extra)
    }

    /// Waits up to `timeout_ms` for one event; `Ok(None)` means timeout.
    pub fn poll(&self, timeout_ms: u32) -> Result<Option<Event>, Error> {
        let mut raw = ffi::zigram_event::default();
        let status = unsafe { ffi::zigram_poll_event(self.handle, timeout_ms, &mut raw) };
        match status {
            1 => Ok(Some(Event { raw })),
            0 => Ok(None),
            _ => Err(Error::PollFailed),
        }
    }

    /// The C ABI version string reported by the core.
    pub fn version() -> String {
        unsafe { CStr::from_ptr(ffi::zigram_version()) }
            .to_string_lossy()
            .into_owned()
    }
}

impl Drop for Core {
    fn drop(&mut self) {
        unsafe { ffi::zigram_stop(self.handle) };
    }
}

/// One TDLib event; its JSON buffer is freed together with the event.
pub struct Event {
    raw: ffi::zigram_event,
}

impl Event {
    /// The raw TDLib JSON, not NUL terminated.
    pub fn json(&self) -> &[u8] {
        if self.raw.json.is_null() {
            return &[];
        }
        unsafe { slice::from_raw_parts(self.raw.json, self.raw.len) }
    }

    /// The `@extra` of the response, if this event answers a request.
    pub fn extra(&self) -> Option<u64> {
        if self.raw.has_extra != 0 {
            Some(self.raw.extra)
        } else {
            None
        }
    }
}

impl Drop for Event {
    fn drop(&mut self) {
        unsafe { ffi::zigram_free(self.raw.json.cast(), self.raw.len) };
    }
}

#[cfg(test)]
mod tests {
    use super::{Core, Error};

    #[test]
    fn version_is_reported() {
        assert!(!Core::version().is_empty());
    }

    #[test]
    fn interior_nul_is_rejected_before_the_call() {
        let err = Core::start("bad\0json").unwrap_err();
        assert!(matches!(err, Error::InteriorNul(_)));
    }
}
