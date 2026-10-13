mod diacritics;
mod source;
mod transform;
mod worker;

pub(crate) mod kitty;
pub(crate) use source::Source;
pub(crate) use transform::{Options, Prepared};

use mlua::{Lua, LuaString, Table};

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
