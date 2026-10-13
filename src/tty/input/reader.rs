use super::super::event::{Event, incoming};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use tokio::sync::mpsc;

const POLL: Duration = Duration::from_millis(100);

pub(crate) struct Reader {
    running: Arc<AtomicBool>,
}

impl Reader {
    pub(crate) fn spawn(sender: mpsc::UnboundedSender<Event>, paused: Arc<AtomicBool>) -> Self {
        let running = Arc::new(AtomicBool::new(true));
        let alive = Arc::clone(&running);
        std::thread::spawn(move || {
            while alive.load(Ordering::Relaxed) {
                if paused.load(Ordering::Relaxed) {
                    std::thread::sleep(POLL);
                    continue;
                }
                if !crossterm::event::poll(POLL).unwrap_or(false) || paused.load(Ordering::Relaxed)
                {
                    continue;
                }
                let Ok(event) = crossterm::event::read() else {
                    return;
                };
                if incoming(event).is_some_and(|event| sender.send(event).is_err()) {
                    return;
                }
            }
        });
        Self { running }
    }

    pub(crate) fn settle() {
        std::thread::sleep(POLL.saturating_add(POLL / 5));
    }
}

impl Drop for Reader {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Relaxed);
    }
}
