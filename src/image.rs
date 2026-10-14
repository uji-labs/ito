mod diacritics;
mod source;
mod transform;
mod worker;

pub(crate) mod kitty;
pub(crate) use source::Source;
pub(crate) use transform::{Options, Prepared};

use mlua::{Lua, LuaString, Table};

// What a screen answers when it is asked to draw an image.
pub(crate) enum Phase {
    Ready,
    Loading,
    Failed(String),
    Unsupported,
}

impl Phase {
    pub(crate) fn name(&self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Loading => "loading",
            Self::Failed(_) => "failed",
            Self::Unsupported => "unsupported",
        }
    }

    pub(crate) fn error(&self) -> Option<&str> {
        match self {
            Self::Failed(problem) => Some(problem),
            _ => None,
        }
    }
}

pub(crate) fn module(lua: &Lua) -> mlua::Result<Table> {
    let module = lua.create_table()?;
    module.set(
        "is_source",
        lua.create_function(|_, value: mlua::Value| {
            Ok(matches!(value, mlua::Value::UserData(data) if data.is::<Source>()))
        })?,
    )?;
    module.set(
        "file",
        lua.create_function(|_, path: String| Ok(Source::file(path)))?,
    )?;
    module.set(
        "bytes",
        lua.create_function(|_, data: LuaString| Source::bytes(&data.as_bytes()))?,
    )?;
    module.set(
        "rgba",
        lua.create_function(|_, (width, height, data): (u32, u32, LuaString)| {
            Source::rgba(width, height, &data.as_bytes())
        })?,
    )?;
    Ok(module)
}
