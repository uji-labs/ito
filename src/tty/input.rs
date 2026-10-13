#[cfg(not(target_family = "wasm"))]
mod reader;
#[cfg(not(target_family = "wasm"))]
pub(crate) use reader::Reader;
#[cfg(target_family = "wasm")]
pub(crate) type Reader = ();

use super::event::Event;
use crate::convert;
use mlua::{AnyUserData, ObjectLike, UserData, UserDataMethods};
#[cfg(not(target_family = "wasm"))]
use std::time::Duration;
use tokio::sync::{Mutex, mpsc};

pub struct Input {
    events: Mutex<mpsc::UnboundedReceiver<Event>>,
    #[cfg(not(target_family = "wasm"))]
    _reader: Option<Reader>,
}

impl Input {
    pub(crate) fn new(events: mpsc::UnboundedReceiver<Event>, reader: Option<Reader>) -> Self {
        #[cfg(target_family = "wasm")]
        let _ = reader;
        Self {
            events: Mutex::new(events),
            #[cfg(not(target_family = "wasm"))]
            _reader: reader,
        }
    }
}

impl Input {
    async fn event(&self) -> Option<Event> {
        self.events.lock().await.recv().await
    }

    #[cfg(not(target_family = "wasm"))]
    fn read(&self, timeout: Option<f64>) -> mlua::Result<Option<Event>> {
        if tokio::runtime::Handle::try_current().is_ok() {
            return Err(mlua::Error::runtime(
                "input:read() blocks, so call input:event() inside an event loop",
            ));
        }
        let limit = timeout
            .map(|seconds| Duration::try_from_secs_f64(seconds.max(0.0)))
            .transpose()
            .map_err(mlua::Error::external)?;
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .map_err(mlua::Error::external)?;
        Ok(runtime.block_on(async {
            match limit {
                Some(limit) => tokio::time::timeout(limit, self.event())
                    .await
                    .ok()
                    .flatten(),
                None => self.event().await,
            }
        }))
    }
}

#[cfg(target_family = "wasm")]
impl Input {
    fn read(&self, _timeout: Option<f64>) -> mlua::Result<Option<Event>> {
        Err(mlua::Error::runtime(
            "input:read() cannot block in a browser; use input:poll() or input:event()",
        ))
    }
}

impl UserData for Input {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("poll", |lua, input, ()| {
            let mut events = input.events.try_lock().map_err(mlua::Error::external)?;
            match events.try_recv().ok() {
                Some(found) => convert::value(lua, &found),
                None => Ok(mlua::Value::Nil),
            }
        });
        methods.add_async_method("event", |lua, input, ()| async move {
            match input.event().await {
                Some(found) => convert::value(&lua, &found),
                None => Ok(mlua::Value::Nil),
            }
        });
        methods.add_function("events", |_, input: AnyUserData| {
            input.get::<mlua::Function>("event")?.bind(input)
        });
        methods.add_method("read", |lua, input, timeout: Option<f64>| {
            match input.read(timeout)? {
                Some(found) => convert::value(lua, &found),
                None => Ok(mlua::Value::Nil),
            }
        });
    }
}
