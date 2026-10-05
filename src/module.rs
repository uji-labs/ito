use mlua::{Function, Lua, Table, Value};

use crate::{FILES, tty};

const ROOT: &str = "ito";
const TERMINAL: &str = "ito.tty";

fn name(path: &str) -> String {
    let stem = path.strip_suffix(".lua").unwrap_or(path);
    stem.strip_suffix("/init").unwrap_or(stem).replace('/', ".")
}

pub fn load(lua: &Lua) -> mlua::Result<Value> {
    let preload: Table = lua.globals().get::<Table>("package")?.get("preload")?;
    let mut root = None;
    for (path, source) in FILES {
        let chunk = lua
            .load(*source)
            .set_name(format!("@{path}"))
            .into_function()?;
        let module = name(path);
        if module == ROOT {
            root = Some(chunk);
        } else {
            preload.set(module, chunk)?;
        }
    }
    preload.set(TERMINAL, lua.create_function(|lua, ()| tty::module(lua))?)?;
    let root: Function = root.ok_or_else(|| mlua::Error::runtime("ito has no init.lua"))?;
    root.call(ROOT)
}
