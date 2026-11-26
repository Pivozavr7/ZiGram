//! Raw C ABI of `libzigram_core.a`. Nothing in this module is safe.

#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_void};

/// Event buffer owned by the caller until `zigram_free` releases it.
#[repr(C)]
pub struct zigram_event {
    pub json: *mut u8,
    pub len: usize,
    pub extra: u64,
    pub has_extra: c_int,
}

impl Default for zigram_event {
    fn default() -> Self {
        zigram_event {
            json: std::ptr::null_mut(),
            len: 0,
            extra: 0,
            has_extra: 0,
        }
    }
}

extern "C" {
    pub fn zigram_version() -> *const c_char;
    pub fn zigram_start(config_json: *const c_char) -> *mut c_void;
    pub fn zigram_stop(handle: *mut c_void);
    pub fn zigram_send(handle: *mut c_void, request_json: *const c_char) -> u64;
    pub fn zigram_send_tdlib_parameters(handle: *mut c_void) -> u64;
    pub fn zigram_poll_event(handle: *mut c_void, timeout_ms: u32, out: *mut zigram_event)
        -> c_int;
    pub fn zigram_free(ptr: *mut c_void, len: usize);
}
