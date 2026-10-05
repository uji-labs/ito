use std::collections::HashMap;
use std::io;

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

#[derive(serde::Deserialize)]
pub(super) struct StyleSpec {
    fg: Option<String>,
    bg: Option<String>,
    #[serde(flatten)]
    flags: HashMap<String, bool>,
}

impl StyleSpec {
    fn color(text: Option<&str>) -> io::Result<Option<Color>> {
        text.map(|text| {
            text.parse::<Color>()
                .map_err(|_| io::Error::other(format!("invalid colour {text}")))
        })
        .transpose()
    }

    pub(super) fn style(&self) -> io::Result<Style> {
        let mut style = Style::default();
        if let Some(fg) = Self::color(self.fg.as_deref())? {
            style = style.fg(fg);
        }
        if let Some(bg) = Self::color(self.bg.as_deref())? {
            style = style.bg(bg);
        }
        Ok(MODIFIERS
            .into_iter()
            .filter(|(name, _)| self.flags.get(*name) == Some(&true))
            .fold(style, |style, (_, modifier)| style.add_modifier(modifier)))
    }
}
