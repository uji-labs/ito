include!(concat!(env!("OUT_DIR"), "/files.rs"));

mod convert;
mod module;
pub mod tty;

pub use module::load;

#[cfg(feature = "module")]
mod entry {
    #[mlua::lua_module(name = "ito")]
    fn ito(lua: &mlua::Lua) -> mlua::Result<mlua::Value> {
        crate::load(lua)
    }
}
