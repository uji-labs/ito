use std::io;

use mlua::Table;
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
    let Some(color) = style.raw_get::<Option<Table>>(field)? else {
        return Ok(None);
    };
    let spec: String = color.raw_get("spec")?;
    spec.parse::<Color>()
        .map(Some)
        .map_err(|_| io::Error::other(format!("invalid colour {spec}")).into())
}

pub(super) fn text_style(style: &Table) -> mlua::Result<Style> {
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
            Ok(if style.raw_get::<Option<bool>>(name)? == Some(true) {
                out.add_modifier(modifier)
            } else {
                out
            })
        })
}
