//! Synchronous Emscripten bridge. JavaScript owns the browser event loop.
#![deny(unsafe_op_in_unsafe_fn)]

use std::cell::{Cell, RefCell};
use std::ffi::{CStr, CString, c_char};
use std::rc::Rc;

use ito::tty::{self, canvas, event::Event};
use mlua::{Function, HookTriggers, Lua, LuaSerdeExt, Table, Value, VmState};
use serde::{Deserialize, Serialize};
use unicode_width::UnicodeWidthStr;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Request {
    Load {
        source: String,
        #[serde(default)]
        view: bool,
        #[serde(default)]
        palette: serde_json::Value,
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
    interaction: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frame: Option<canvas::Frame>,
    #[serde(skip_serializing_if = "Option::is_none")]
    wake: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

/// How the loaded source draws: a plain app that owns its event loop, or a view
/// function that the playground host runs inside a `Window`.
enum Mode {
    App,
    Playground(serde_json::Value),
}

struct Runtime {
    draw: Function,
    handle: canvas::Handle,
    frame: Rc<RefCell<Option<canvas::Frame>>>,
    clock: Rc<Cell<f64>>,
    info: Option<Function>,
    budget: Rc<Cell<u32>>,
    // mlua Function handles are weak references; keep the VM alive between frames.
    _lua: Lua,
}

impl Runtime {
    fn open(source: &str, width: u16, height: u16, now: f64, mode: Mode) -> mlua::Result<Self> {
        let lua = Lua::new();
        lua.set_memory_limit(64 * 1024 * 1024)?;
        let budget = Rc::new(Cell::new(0));
        let instructions = Rc::clone(&budget);
        lua.set_hook(
            HookTriggers::new().every_nth_instruction(10_000),
            move |_, _| {
                let used = instructions.get() + 1;
                instructions.set(used);
                if used > 500 {
                    return Err(mlua::Error::runtime(
                        "This script took too long. Check for an endless loop.",
                    ));
                }
                Ok(VmState::Continue)
            },
        )?;
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
        let draw: Function = lua
            .load(source)
            .set_name(match mode {
                Mode::App => "@canvas-app.lua",
                Mode::Playground(_) => "@playground.lua",
            })
            .eval()?;
        let (draw, info) = match mode {
            Mode::App => (draw, None),
            Mode::Playground(palette) => {
                let host: Function = lua
                    .load(include_str!("../playground.lua"))
                    .set_name("@playground-host.lua")
                    .eval()?;
                let app: Table = host.call((draw, lua.to_value(&palette)?))?;
                (
                    app.get::<Function>("draw")?,
                    Some(app.get::<Function>("info")?),
                )
            }
        };
        Ok(Self {
            draw,
            handle,
            frame,
            clock,
            info,
            budget,
            _lua: lua,
        })
    }

    fn render(&self, now: f64) -> mlua::Result<Response> {
        self.clock.set(now);
        self.budget.set(0);
        let wake: Option<f64> = self.draw.call(())?;
        let interaction: Option<serde_json::Value> = self
            .info
            .as_ref()
            .map(|info| self._lua.from_value(info.call::<Value>(())?))
            .transpose()?;
        let mut frame = self.frame.take();
        if let Some(height) = interaction
            .as_ref()
            .and_then(|info| info["height"].as_u64())
            && let Some(frame) = frame.as_mut()
        {
            frame.height = (height as u16).min(frame.height);
            frame.cells.retain(|cell| cell.row < frame.height);
        }
        Ok(Response {
            interaction,
            frame,
            wake: wake.filter(|seconds| seconds.is_finite() && *seconds >= 0.0),
            error: None,
        })
    }
}

thread_local! {
    static RUNTIME: RefCell<Option<Runtime>> = const { RefCell::new(None) };
    static RESPONSE: RefCell<CString> = RefCell::new(CString::default());
}

/// A frame stays small, however large the browser makes the canvas.
const MOST: (u16, u16) = (160, 120);

fn bounds(width: u16, height: u16) -> (u16, u16) {
    let (most_width, most_height) = MOST;
    (width.clamp(1, most_width), height.clamp(1, most_height))
}

fn dispatch(request: Request) -> mlua::Result<Response> {
    RUNTIME.with_borrow_mut(|slot| match request {
        Request::Load {
            source,
            view,
            palette,
            width,
            height,
            now,
        } => {
            let (width, height) = bounds(width, height);
            let mode = if view {
                Mode::Playground(palette)
            } else {
                Mode::App
            };
            let runtime = Runtime::open(&source, width, height, now, mode)?;
            let response = runtime.render(now)?;
            *slot = Some(runtime);
            Ok(response)
        }
        Request::Close => {
            *slot = None;
            Ok(Response::default())
        }
        Request::Frame { now } => live(slot)?.render(now),
        Request::Event { event, now } => {
            let runtime = live(slot)?;
            runtime.handle.send(event);
            runtime.render(now)
        }
        Request::Resize { width, height, now } => {
            let runtime = live(slot)?;
            let (width, height) = bounds(width, height);
            runtime.handle.resize(width, height);
            runtime.render(now)
        }
    })
}

fn live(slot: &Option<Runtime>) -> mlua::Result<&Runtime> {
    slot.as_ref()
        .ok_or_else(|| mlua::Error::runtime("load a Canvas app first"))
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

    fn shown(response: &Response) -> String {
        response
            .frame
            .as_ref()
            .unwrap()
            .cells
            .iter()
            .map(|cell| cell.text.as_str())
            .collect()
    }

    fn key(runtime: &Runtime, key: &str) -> mlua::Result<Response> {
        runtime.handle.send(Event::Key {
            key: key.into(),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
            repeat: false,
        });
        runtime.render(0.2)
    }

    /// A runtime in playground mode: `source` returns a view function, and the
    /// fixed host theme stands in for the browser palette.
    fn playground(source: &str, width: u16, height: u16) -> mlua::Result<Runtime> {
        Runtime::open(
            source,
            width,
            height,
            0.0,
            Mode::Playground(serde_json::json!({})),
        )
    }

    #[test]
    fn canvas_uses_terminal_focus_and_state_transitions() -> mlua::Result<()> {
        let runtime = playground(include_str!("../examples/flow.lua"), 48, 120)?;
        assert!(shown(&runtime.render(0.0)?).contains("CHOOSE AN ITEM"));
        runtime.handle.send(Event::Focus { focused: true });
        runtime.render(0.1)?;
        key(&runtime, "down")?;
        let edit = key(&runtime, "enter")?;
        assert!(shown(&edit).contains("EDIT NAME"));
        assert_eq!(
            edit.interaction.as_ref().unwrap()["focus"]["text_input"],
            true
        );
        runtime.handle.send(Event::Paste {
            text: " together".into(),
        });
        assert!(shown(&runtime.render(0.2)?).contains("Read a chapter together"));
        assert!(shown(&key(&runtime, "esc")?).contains("CHOOSE AN ITEM"));
        key(&runtime, "enter")?;
        assert!(shown(&key(&runtime, "enter")?).contains("REVIEW"));
        assert!(shown(&key(&runtime, "esc")?).contains("EDIT NAME"));
        key(&runtime, "enter")?;
        let saved = key(&runtime, "enter")?;
        assert!(shown(&saved).contains("SAVED"));
        assert!(!shown(&saved).contains("together"));
        assert_eq!(
            saved.interaction.as_ref().unwrap()["focus"]["text_input"],
            false
        );
        Ok(())
    }

    #[test]
    fn all_presets_draw_terminal_cells_at_phone_width() -> mlua::Result<()> {
        for source in [
            include_str!("../examples/counter.lua"),
            include_str!("../examples/list.lua"),
            include_str!("../examples/settings.lua"),
            include_str!("../examples/shop.lua"),
        ] {
            let runtime = playground(source, 28, 120)?;
            let response = runtime.render(0.0)?;
            let frame = response.frame.unwrap();
            assert!(frame.height > 1 && frame.height < 120);
            assert!(
                frame
                    .cells
                    .iter()
                    .all(|cell| cell.col + cell.width <= frame.width)
            );
        }
        Ok(())
    }

    #[test]
    fn canvas_stops_endless_scripts() {
        assert!(playground("while true do end", 40, 20).is_err());
        let runtime = playground("return function() while true do end end", 40, 20).unwrap();
        assert!(runtime.render(0.0).is_err());
    }

    #[test]
    fn lua_survives_across_browser_frames_and_input() -> mlua::Result<()> {
        let runtime = Runtime::open(include_str!("../demo.lua"), 80, 24, 0.0, Mode::App)?;
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
