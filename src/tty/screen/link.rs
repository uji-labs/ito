use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::io;
use std::num::NonZeroU16;

use ratatui::buffer::{Buffer, CellDiffOption, CellWidth};

const CLOSE: &str = "\x1b]8;;\x1b\\";
const PREFIX: &str = "\x1b]8;id=ito-";

pub(super) struct Link {
    open: String,
}

impl Link {
    pub(super) fn new(url: &str) -> io::Result<Self> {
        if url.is_empty() || url.chars().any(char::is_control) {
            return Err(io::Error::other(
                "a link needs a non-empty URL without control characters",
            ));
        }
        let mut hash = DefaultHasher::new();
        url.hash(&mut hash);
        Ok(Self {
            open: format!("{PREFIX}{:x};{url}\x1b\\", hash.finish()),
        })
    }

    pub(super) fn apply(link: Option<&Self>, buffer: &mut Buffer, row: u16, from: u16, to: u16) {
        let mut col = from;
        while col < to {
            let Some(cell) = buffer.cell_mut((col, row)) else {
                break;
            };
            cell.set_diff_option(CellDiffOption::None);
            let width = cell.cell_width().max(1);
            if let Some(link) = link {
                let symbol = format!("{}{}{CLOSE}", link.open, cell.symbol());
                cell.set_symbol(&symbol);
                cell.set_diff_option(CellDiffOption::ForcedWidth(
                    NonZeroU16::new(width).unwrap_or(NonZeroU16::MIN),
                ));
            }
            col = col.saturating_add(width);
        }
    }

    pub(super) fn split(symbol: &str) -> (Option<&str>, &str) {
        let parsed = symbol
            .strip_prefix(PREFIX)
            .and_then(|rest| rest.split_once(';'))
            .and_then(|(_, rest)| rest.split_once("\x1b\\"))
            .and_then(|(url, rest)| rest.strip_suffix(CLOSE).map(|text| (url, text)));
        parsed.map_or((None, symbol), |(url, text)| (Some(url), text))
    }
}
