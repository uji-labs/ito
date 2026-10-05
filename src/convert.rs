use mlua::serde::SerializeOptions;
use mlua::{Lua, LuaSerdeExt, Value};
use serde::Serialize;
use serde::de::DeserializeOwned;

pub(crate) fn options<T: DeserializeOwned>(lua: &Lua, value: Value) -> mlua::Result<T> {
    let value = match value {
        Value::Nil => Value::Table(lua.create_table()?),
        value => value,
    };
    lua.from_value(value)
}

pub(crate) fn value(lua: &Lua, value: &impl Serialize) -> mlua::Result<Value> {
    lua.to_value_with(
        value,
        SerializeOptions::new()
            .serialize_none_to_null(false)
            .serialize_unit_to_null(false),
    )
}
