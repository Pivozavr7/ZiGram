//! Turns the blocking C API poll into an iced stream.
//!
//! One dedicated thread calls `zigram_poll_event`; events cross into the
//! ui as messages on an mpsc channel. The thread exits as soon as the
//! receiver is gone, which is what happens when the window closes.

use std::sync::Arc;
use std::thread;
use std::time::Duration;

use iced::futures::channel::mpsc;
use iced::futures::Stream;

use crate::app::Message;
use iced_shell::Core;

/// Events buffered before the poll thread has to wait for the ui.
const QUEUE_CAPACITY: usize = 64;

/// How long `zigram_poll_event` waits per call; also bounds how fast the
/// thread notices that the receiver is gone.
const POLL_TIMEOUT_MS: u32 = 200;

/// How long the thread waits when the queue is full.
const RETRY_DELAY: Duration = Duration::from_millis(20);

/// Starts the poll thread and returns the stream of events for the app.
pub fn start(core: Arc<Core>) -> impl Stream<Item = Message> {
    let (mut sender, receiver) = mpsc::channel(QUEUE_CAPACITY);
    thread::spawn(move || {
        loop {
            match core.poll(POLL_TIMEOUT_MS) {
                Ok(Some(event)) => {
                    let (json, extra) = event.into_parts();
                    if !send_blocking(&mut sender, Message::Event { json, extra }) {
                        break; // window closed
                    }
                }
                Ok(None) => continue, // timeout, keep waiting
                Err(_) => break,      // poll failed
            }
        }
    });
    receiver
}

/// Sends one message, waiting while the queue is full. Returns false when
/// the receiver is gone.
fn send_blocking(sender: &mut mpsc::Sender<Message>, message: Message) -> bool {
    let mut message = message;
    loop {
        match sender.try_send(message) {
            Ok(()) => return true,
            Err(err) if err.is_full() => {
                message = err.into_inner();
                thread::sleep(RETRY_DELAY);
            }
            Err(_) => return false,
        }
    }
}
