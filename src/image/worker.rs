use std::sync::{Arc, OnceLock, mpsc};

pub(super) type Job = Box<dyn FnOnce() + Send>;

#[derive(Clone, Copy)]
pub(super) enum Unavailable {
    Full,
    Stopped,
    Failed,
}

impl std::fmt::Display for Unavailable {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(match self {
            Self::Full => "image worker is busy",
            Self::Stopped => "image worker has stopped",
            Self::Failed => "image worker could not be started",
        })
    }
}

// One worker and a bounded queue keep resizing galleries from spawning threads
// or retaining an unbounded number of obsolete transformations.
pub(super) fn submit(job: Job) -> Result<(), (Unavailable, Job)> {
    static WORKER: OnceLock<Result<mpsc::SyncSender<Job>, String>> = OnceLock::new();
    let worker = WORKER.get_or_init(|| {
        let (sender, receiver) = mpsc::sync_channel::<Job>(8);
        std::thread::Builder::new()
            .name("ito-images".into())
            .spawn(move || {
                for job in receiver {
                    job();
                }
            })
            .map_err(|error| error.to_string())?;
        Ok(sender)
    });
    let Ok(sender) = worker else {
        return Err((Unavailable::Failed, job));
    };
    sender.try_send(job).map_err(|error| match error {
        mpsc::TrySendError::Full(job) => (Unavailable::Full, job),
        mpsc::TrySendError::Disconnected(job) => (Unavailable::Stopped, job),
    })
}

// Computes off the UI thread, and does nothing when nobody is left waiting for
// the result. The slot is the caller's handle on the work.
pub(super) fn lazy<T: Send + Sync + 'static>(
    compute: impl FnOnce() -> T + Send + 'static,
) -> (Arc<OnceLock<T>>, Job) {
    let slot = Arc::new(OnceLock::new());
    let weak = Arc::downgrade(&slot);
    let job: Job = Box::new(move || {
        if weak.strong_count() == 0 {
            return;
        }
        let value = compute();
        if let Some(slot) = weak.upgrade() {
            let _ = slot.set(value);
        }
    });
    (slot, job)
}
