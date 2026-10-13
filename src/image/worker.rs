use std::sync::{OnceLock, mpsc};

pub(super) type Job = Box<dyn FnOnce() + Send>;

// One worker and a bounded queue keep resizing galleries from spawning threads
// or retaining an unbounded number of obsolete transformations.
pub(super) fn submit(job: Job) -> Result<(), (String, Job)> {
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
    let sender = match worker {
        Ok(sender) => sender,
        Err(error) => return Err((error.clone(), job)),
    };
    sender.try_send(job).map_err(|error| match error {
        mpsc::TrySendError::Full(job) => ("image worker is busy".into(), job),
        mpsc::TrySendError::Disconnected(job) => ("image worker has stopped".into(), job),
    })
}
