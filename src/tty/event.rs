#[cfg(not(target_family = "wasm"))]
use crossterm::event::{
    Event as NativeEvent, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
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

#[cfg(not(target_family = "wasm"))]
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

#[cfg(not(target_family = "wasm"))]
fn key(key: KeyEvent) -> Option<Event> {
    if key.kind == KeyEventKind::Release {
        return None;
    }
    Some(Event::Key {
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

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Motion {
    Down,
    Up,
    Drag,
    Move,
    ScrollUp,
    ScrollDown,
    ScrollLeft,
    ScrollRight,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Button {
    Left,
    Right,
    Middle,
}

#[cfg(not(target_family = "wasm"))]
fn button(button: MouseButton) -> Button {
    match button {
        MouseButton::Left => Button::Left,
        MouseButton::Right => Button::Right,
        MouseButton::Middle => Button::Middle,
    }
}

#[cfg(not(target_family = "wasm"))]
fn mouse(mouse: MouseEvent) -> Event {
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
    Event::Mouse {
        kind,
        button: pressed,
        row: mouse.row,
        col: mouse.column,
        ctrl: mouse.modifiers.contains(KeyModifiers::CONTROL),
        alt: mouse.modifiers.contains(KeyModifiers::ALT),
        shift: mouse.modifiers.contains(KeyModifiers::SHIFT),
    }
}

#[cfg(not(target_family = "wasm"))]
pub(crate) fn incoming(event: NativeEvent) -> Option<Event> {
    match event {
        NativeEvent::Key(pressed) => key(pressed),
        NativeEvent::Mouse(moved) => Some(mouse(moved)),
        NativeEvent::Paste(text) => Some(Event::Paste { text }),
        NativeEvent::Resize(width, height) => Some(Event::Resize { width, height }),
        NativeEvent::FocusGained => Some(Event::Focus { focused: true }),
        NativeEvent::FocusLost => Some(Event::Focus { focused: false }),
    }
}
