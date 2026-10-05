use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use crossterm::event::{
    Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use mlua::{AnyUserData, ObjectLike, UserData, UserDataMethods};
use tokio::sync::{Mutex, mpsc};

use crate::convert;

const POLL: Duration = Duration::from_millis(100);

#[derive(serde::Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Incoming {
    Key {
        key: String,
        ctrl: bool,
        alt: bool,
        shift: bool,
        meta: bool,
        repeat: bool,
    },
    Mouse {
        kind: Motion,
        button: Option<Button>,
        row: u16,
        col: u16,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },
    Paste {
        text: String,
    },
    Resize {
        width: u16,
        height: u16,
    },
    Focus {
        focused: bool,
    },
}

fn key_name(code: KeyCode) -> Option<String> {
    let name = match code {
        KeyCode::Char(ch) => return Some(ch.to_string()),
        KeyCode::F(number) => return Some(format!("f{number}")),
        KeyCode::Enter => "enter",
        KeyCode::Esc => "esc",
        KeyCode::Backspace => "backspace",
        KeyCode::Delete => "delete",
        KeyCode::Tab => "tab",
        KeyCode::BackTab => "backtab",
        KeyCode::Left => "left",
        KeyCode::Right => "right",
        KeyCode::Up => "up",
        KeyCode::Down => "down",
        KeyCode::Home => "home",
        KeyCode::End => "end",
        KeyCode::PageUp => "pageup",
        KeyCode::PageDown => "pagedown",
        KeyCode::Insert => "insert",
        _ => return None,
    };
    Some(name.to_string())
}

fn key(key: KeyEvent) -> Option<Incoming> {
    if key.kind == KeyEventKind::Release {
        return None;
    }
    Some(Incoming::Key {
        key: key_name(key.code)?,
        ctrl: key.modifiers.contains(KeyModifiers::CONTROL),
        alt: key.modifiers.contains(KeyModifiers::ALT),
        shift: key.modifiers.contains(KeyModifiers::SHIFT),
        meta: key
            .modifiers
            .intersects(KeyModifiers::SUPER | KeyModifiers::META),
        repeat: key.kind == KeyEventKind::Repeat,
    })
}

#[derive(serde::Serialize)]
#[serde(rename_all = "snake_case")]
enum Motion {
    Down,
    Up,
    Drag,
    Move,
    ScrollUp,
    ScrollDown,
    ScrollLeft,
    ScrollRight,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "lowercase")]
enum Button {
    Left,
    Right,
    Middle,
}

fn button(button: MouseButton) -> Button {
    match button {
        MouseButton::Left => Button::Left,
        MouseButton::Right => Button::Right,
        MouseButton::Middle => Button::Middle,
    }
}

fn mouse(mouse: MouseEvent) -> Incoming {
    let (kind, pressed) = match mouse.kind {
        MouseEventKind::Down(pressed) => (Motion::Down, Some(button(pressed))),
        MouseEventKind::Up(pressed) => (Motion::Up, Some(button(pressed))),
        MouseEventKind::Drag(pressed) => (Motion::Drag, Some(button(pressed))),
        MouseEventKind::Moved => (Motion::Move, None),
        MouseEventKind::ScrollUp => (Motion::ScrollUp, None),
        MouseEventKind::ScrollDown => (Motion::ScrollDown, None),
        MouseEventKind::ScrollLeft => (Motion::ScrollLeft, None),
        MouseEventKind::ScrollRight => (Motion::ScrollRight, None),
    };
    Incoming::Mouse {
        kind,
        button: pressed,
        row: mouse.row,
        col: mouse.column,
        ctrl: mouse.modifiers.contains(KeyModifiers::CONTROL),
        alt: mouse.modifiers.contains(KeyModifiers::ALT),
        shift: mouse.modifiers.contains(KeyModifiers::SHIFT),
    }
}

fn incoming(event: Event) -> Option<Incoming> {
    match event {
        Event::Key(pressed) => key(pressed),
        Event::Mouse(moved) => Some(mouse(moved)),
        Event::Paste(text) => Some(Incoming::Paste { text }),
        Event::Resize(width, height) => Some(Incoming::Resize { width, height }),
        Event::FocusGained => Some(Incoming::Focus { focused: true }),
        Event::FocusLost => Some(Incoming::Focus { focused: false }),
    }
}

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
                if sender.send(event).is_err() {
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

pub struct Input {
    events: Mutex<mpsc::UnboundedReceiver<Event>>,
    _reader: Option<Reader>,
}

impl Input {
    pub(crate) fn new(events: mpsc::UnboundedReceiver<Event>, reader: Option<Reader>) -> Self {
        Self {
            events: Mutex::new(events),
            _reader: reader,
        }
    }
}

impl Input {
    async fn event(&self) -> Option<Incoming> {
        let mut events = self.events.lock().await;
        loop {
            if let Some(found) = incoming(events.recv().await?) {
                return Some(found);
            }
        }
    }

    fn read(&self, timeout: Option<f64>) -> mlua::Result<Option<Incoming>> {
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

impl UserData for Input {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
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
