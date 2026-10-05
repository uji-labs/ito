use std::io;

use mlua::{LuaString, Table};
use ratatui::style::{Color, Modifier, Style};

pub(super) const MODIFIERS: [(&str, Modifier); 7] = [
    ("bold", Modifier::BOLD),
    ("blink", Modifier::SLOW_BLINK),
    ("dim", Modifier::DIM),
    ("italic", Modifier::ITALIC),
    ("underline", Modifier::UNDERLINED),
    ("reverse", Modifier::REVERSED),
    ("strikethrough", Modifier::CROSSED_OUT),
];

fn color(style: &Table, field: &str) -> mlua::Result<Option<Color>> {
    let Some(color) = style.get::<Option<Table>>(field)? else {
        return Ok(None);
    };
    let spec: String = color.get("spec")?;
    spec.parse::<Color>()
        .map(Some)
        .map_err(|_| io::Error::other(format!("invalid colour {spec}")).into())
}

const NAME: &[u8] = b"ito.TextStyle";

fn named(style: &Table) -> mlua::Result<bool> {
    let Some(meta) = style.metatable() else {
        return Ok(false);
    };
    let name: Option<LuaString> = meta.raw_get("__name")?;
    Ok(name.is_some_and(|name| name.as_bytes().as_ref() == NAME))
}

pub(super) fn text_style(style: &Table) -> mlua::Result<Style> {
    if !named(style)? {
        return Err(io::Error::other("a style is an ito.TextStyle, not a table").into());
    }
    let mut out = Style::default();
    if let Some(fg) = color(style, "foreground")? {
        out = out.fg(fg);
    }
    if let Some(bg) = color(style, "background")? {
        out = out.bg(bg);
    }
    MODIFIERS
        .into_iter()
        .try_fold(out, |out, (name, modifier)| {
            Ok(if style.get::<Option<bool>>(name)? == Some(true) {
                out.add_modifier(modifier)
            } else {
                out
            })
        })
}
