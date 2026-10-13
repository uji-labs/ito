//! Synchronous Emscripten bridge. JavaScript owns the browser event loop.
#![deny(unsafe_op_in_unsafe_fn)]

use std::cell::{Cell, RefCell};
use std::ffi::{CStr, CString, c_char};
use std::rc::Rc;

use ito::tty::{self, canvas, event::Event};
use mlua::{Function, Lua, Table};
use serde::{Deserialize, Serialize};
use unicode_width::UnicodeWidthStr;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Request {
    Load {
        source: String,
        width: u16,
        height: u16,
        now: f64,
    },
    Frame {
        now: f64,
    },
    Event {
        event: Event,
        now: f64,
    },
    Resize {
        width: u16,
        height: u16,
        now: f64,
    },
    Close,
}

#[derive(Default, Serialize)]
struct Response {
    #[serde(skip_serializing_if = "Option::is_none")]
    frame: Option<canvas::Frame>,
    #[serde(skip_serializing_if = "Option::is_none")]
    wake: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

struct Runtime {
    draw: Function,
    handle: canvas::Handle,
    frame: Rc<RefCell<Option<canvas::Frame>>>,
    clock: Rc<Cell<f64>>,
    // mlua Function handles are weak references; keep the VM alive between frames.
    _lua: Lua,
}

impl Runtime {
    fn new(source: &str, width: u16, height: u16, now: f64) -> mlua::Result<Self> {
        let lua = Lua::new();
        let frame = Rc::new(RefCell::new(None));
        let published = Rc::clone(&frame);
        let (terminal, handle) = canvas::terminal(width, height, move |frame| {
            published.replace(Some(frame));
            Ok(())
        });
        tty::provide(&lua, terminal);
        let ito = ito::load(&lua)?;
        lua.globals()
            .get::<Table>("package")?
            .get::<Table>("loaded")?
            .set("ito", ito)?;
        let clock = Rc::new(Cell::new(now));
        let time = Rc::clone(&clock);
        let opts = lua.create_table()?;
        opts.set("clock", lua.create_function(move |_, ()| Ok(time.get()))?)?;
        opts.set(
            "width",
            lua.create_function(|_, text: String| Ok(text.width()))?,
        )?;
        let host: Table = lua.load("return require('ito.host')").eval()?;
        host.get::<Function>("setup")?.call::<()>(opts)?;
        let draw: Function = lua.load(source).set_name("@canvas-app.lua").eval()?;
        Ok(Self {
            draw,
            handle,
            frame,
            clock,
            _lua: lua,
        })
    }

    fn render(&self, now: f64) -> mlua::Result<Response> {
        self.clock.set(now);
        let wake: Option<f64> = self.draw.call(())?;
        Ok(Response {
            frame: self.frame.take(),
            wake: wake.filter(|seconds| seconds.is_finite() && *seconds >= 0.0),
            error: None,
        })
    }
}

thread_local! {
    static RUNTIME: RefCell<Option<Runtime>> = const { RefCell::new(None) };
    static RESPONSE: RefCell<CString> = RefCell::new(CString::default());
}

fn dispatch(request: Request) -> mlua::Result<Response> {
    RUNTIME.with_borrow_mut(|slot| {
        if let Request::Load {
            source,
            width,
            height,
            now,
        } = request
        {
            let runtime = Runtime::new(&source, width, height, now)?;
            let response = runtime.render(now)?;
            *slot = Some(runtime);
            return Ok(response);
        }
        if matches!(request, Request::Close) {
            *slot = None;
            return Ok(Response::default());
        }
        let runtime = slot
            .as_ref()
            .ok_or_else(|| mlua::Error::runtime("load a Canvas app first"))?;
        let now = match request {
            Request::Frame { now } => now,
            Request::Event { event, now } => {
                runtime.handle.send(event);
                now
            }
            Request::Resize { width, height, now } => {
                runtime.handle.resize(width, height);
                now
            }
            Request::Load { .. } | Request::Close => unreachable!(),
        };
        runtime.render(now)
    })
}

/// Called by Emscripten `ccall` with a NUL-terminated JSON string.
/// The result remains valid until the next call. JavaScript copies it immediately.
///
/// # Safety
/// `request` must point to a valid NUL-terminated string for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ito_call(request: *const c_char) -> *const c_char {
    let result = if request.is_null() {
        Err(mlua::Error::runtime("missing browser request"))
    } else {
        // SAFETY: ccall owns the input string until this function returns.
        let bytes = unsafe { CStr::from_ptr(request) }.to_bytes();
        serde_json::from_slice(bytes)
            .map_err(mlua::Error::external)
            .and_then(dispatch)
    };
    let response = result.unwrap_or_else(|error| Response {
        error: Some(error.to_string()),
        ..Response::default()
    });
    // JSON escapes embedded NULs, so the serialized bytes are a valid C string.
    let json = serde_json::to_vec(&response)
        .unwrap_or_else(|_| br#"{"error":"could not encode frame"}"#.to_vec());
    RESPONSE.with_borrow_mut(|output| {
        *output = CString::new(json).unwrap_or_default();
        output.as_ptr()
    })
}

fn main() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lua_survives_across_browser_frames_and_input() -> mlua::Result<()> {
        let runtime = Runtime::new(include_str!("../demo.lua"), 80, 24, 0.0)?;
        let first = runtime.render(0.1)?;
        let text = |response: Response| {
            response
                .frame
                .map(|frame| {
                    frame
                        .cells
                        .into_iter()
                        .map(|cell| cell.text)
                        .collect::<String>()
                })
                .unwrap_or_default()
        };
        assert!(text(first).contains("Ito, running on Canvas"));
        runtime.handle.send(Event::Key {
            key: "x".into(),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
            repeat: false,
        });
        runtime.render(0.2)?;
        runtime.handle.send(Event::Key {
            key: "enter".into(),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
            repeat: false,
        });
        assert!(text(runtime.render(0.3)?).contains("You wrote: x"));
        Ok(())
    }
}
