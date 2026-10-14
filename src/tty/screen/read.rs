use ratatui::buffer::Buffer;
use ratatui::style::{Color, Style};

use super::link::Link;
use super::style::MODIFIERS;
use crate::image::kitty;

#[derive(serde::Serialize)]
pub(super) struct Run {
    text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    link: Option<String>,
    fg: Option<String>,
    bg: Option<String>,
    modifiers: Vec<&'static str>,
}

fn shade(color: Color) -> Option<String> {
    (color != Color::Reset).then(|| color.to_string())
}

pub(super) fn runs(buffer: &Buffer, row: u16) -> Vec<Run> {
    let area = buffer.area;
    let mut out: Vec<(Style, Option<&str>, String)> = Vec::new();
    for col in area.left()..area.right() {
        let cell = &buffer[(col, row)];
        let style = cell.style();
        let (link, symbol) = Link::split(cell.symbol());
        let symbol = if kitty::is_placeholder(symbol) {
            " "
        } else {
            symbol
        };
        match out.last_mut() {
            Some((last, last_link, text)) if *last == style && *last_link == link => {
                text.push_str(symbol);
            }
            _ => out.push((style, link, symbol.to_string())),
        }
    }
    out.into_iter()
        .map(|(style, link, text)| Run {
            text,
            link: link.map(str::to_string),
            fg: style.fg.and_then(shade),
            bg: style.bg.and_then(shade),
            modifiers: MODIFIERS
                .into_iter()
                .filter(|(_, modifier)| style.add_modifier.contains(*modifier))
                .map(|(name, _)| name)
                .collect(),
        })
        .collect()
}

pub(crate) fn row_text(buffer: &Buffer, row: u16) -> String {
    let area = buffer.area;
    (area.left()..area.right())
        .map(|col| {
            let symbol = Link::split(buffer[(col, row)].symbol()).1;
            if kitty::is_placeholder(symbol) {
                " "
            } else {
                symbol
            }
        })
        .collect()
}
