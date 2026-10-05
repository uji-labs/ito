use ratatui::buffer::Buffer;
use ratatui::style::{Color, Style};

use super::style::MODIFIERS;

#[derive(serde::Serialize)]
pub(super) struct Run {
    text: String,
    fg: Option<String>,
    bg: Option<String>,
    modifiers: Vec<&'static str>,
}

fn shade(color: Color) -> Option<String> {
    (color != Color::Reset).then(|| color.to_string())
}

pub(super) fn runs(buffer: &Buffer, row: u16) -> Vec<Run> {
    let area = buffer.area;
    let mut out: Vec<(Style, String)> = Vec::new();
    for col in area.left()..area.right() {
        let cell = &buffer[(col, row)];
        let style = cell.style();
        match out.last_mut() {
            Some((last, text)) if *last == style => text.push_str(cell.symbol()),
            _ => out.push((style, cell.symbol().to_string())),
        }
    }
    out.into_iter()
        .map(|(style, text)| Run {
            text,
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
        .map(|col| buffer[(col, row)].symbol())
        .collect()
}
