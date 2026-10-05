mod input;
mod real;
mod screen;
mod surface;
mod virtual_screen;

use std::io;

use crossterm::event::Event;
use mlua::{AnyUserData, Lua, Table};
use tokio::sync::{mpsc, watch};

pub use input::Input;
pub use screen::Screen;

const OPENED: &str = "ito.terminal";

pub enum Terminal {
    Real,
    Virtual(VirtualTerminal),
    Open(Screen, Input),
}

pub struct VirtualTerminal {
    events: mpsc::UnboundedReceiver<Event>,
    frames: watch::Sender<Vec<String>>,
    size: watch::Receiver<(u16, u16)>,
}

pub struct VirtualHandle {
    events: mpsc::UnboundedSender<Event>,
    frames: watch::Receiver<Vec<String>>,
    size: watch::Sender<(u16, u16)>,
}

impl VirtualHandle {
    pub fn send(&self, event: Event) -> bool {
        self.events.send(event).is_ok()
    }

    pub fn resize(&self, width: u16, height: u16) -> bool {
        self.size.send((width, height)).is_ok() && self.send(Event::Resize(width, height))
    }

    pub fn frame(&self) -> Vec<String> {
        self.frames.borrow().clone()
    }

    pub fn frames(&self) -> watch::Receiver<Vec<String>> {
        self.frames.clone()
    }
}

pub fn virtual_terminal(width: u16, height: u16) -> (VirtualTerminal, VirtualHandle) {
    let (sender, events) = mpsc::unbounded_channel();
    let (published, frames) = watch::channel(Vec::new());
    let (resized, size) = watch::channel((width, height));
    (
        VirtualTerminal {
            events,
            frames: published,
            size,
        },
        VirtualHandle {
            events: sender,
            frames,
            size: resized,
        },
    )
}

pub fn open(terminal: Terminal) -> io::Result<(Screen, Input)> {
    match terminal {
        Terminal::Real => real::open(),
        Terminal::Virtual(terminal) => Ok(virtual_screen::open(terminal)),
        Terminal::Open(screen, input) => Ok((screen, input)),
    }
}

pub fn provide(lua: &Lua, terminal: Terminal) {
    lua.set_app_data(terminal);
}

pub fn reclaim(lua: &Lua) -> Option<Terminal> {
    let Some((screen, input)) = opened(lua).ok().flatten() else {
        return lua.remove_app_data::<Terminal>();
    };
    Some(Terminal::Open(
        screen.take::<Screen>().ok()?.forget(),
        input.take::<Input>().ok()?,
    ))
}

fn opened(lua: &Lua) -> mlua::Result<Option<(AnyUserData, AnyUserData)>> {
    let Some(handles) = lua.named_registry_value::<Option<Table>>(OPENED)? else {
        return Ok(None);
    };
    Ok(Some((handles.get(1)?, handles.get(2)?)))
}

fn handles(lua: &Lua, (): ()) -> mlua::Result<(AnyUserData, AnyUserData)> {
    if let Some(handles) = opened(lua)? {
        return Ok(handles);
    }
    let terminal = lua.remove_app_data::<Terminal>().unwrap_or(Terminal::Real);
    let (screen, input) = open(terminal).map_err(mlua::Error::external)?;
    let handles = (lua.create_userdata(screen)?, lua.create_userdata(input)?);
    lua.set_named_registry_value(OPENED, [handles.0.clone(), handles.1.clone()])?;
    Ok(handles)
}

pub(crate) fn module(lua: &Lua) -> mlua::Result<Table> {
    let module = lua.create_table()?;
    module.set("open", lua.create_function(handles)?)?;
    Ok(module)
}

pub fn restore() {
    real::restore();
}
