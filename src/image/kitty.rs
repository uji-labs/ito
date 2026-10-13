use std::collections::{HashMap, HashSet};
use std::io::{self, Write};
use std::num::NonZeroU16;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use base64::{Engine, engine::general_purpose::STANDARD};
use ratatui::buffer::{Buffer, Cell, CellDiffOption};
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier};
use serde::{Deserialize, Serialize};

use super::diacritics::DIACRITICS;
use super::{Options, Prepared, Source};

const PLACEHOLDER: char = '\u{10eeee}';
const CACHE_BUDGET: u64 = 64 * 1024 * 1024;
const MAX_ENTRIES: usize = 64;

#[derive(Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Protocol {
    #[default]
    Off,
    Kitty,
}

#[derive(Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct Config {
    pub protocol: Protocol,
    pub cell_width: u16,
    pub cell_height: u16,
    pub tmux: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            protocol: Protocol::Off,
            cell_width: 8,
            cell_height: 16,
            tmux: false,
        }
    }
}

#[derive(Clone, Hash, PartialEq, Eq)]
struct Key {
    source: u64,
    options: Options,
    cols: u16,
    rows: u16,
    cell_width: u16,
    cell_height: u16,
}

struct Entry {
    id: u32,
    prepared: Prepared,
    seen: u64,
    cost: u64,
    uploaded: bool,
}

#[derive(Default)]
pub(crate) struct Images {
    pub config: Config,
    entries: HashMap<Key, Entry>,
    retired: Vec<(u32, bool)>,
    generation: u64,
}

fn next_id() -> u32 {
    static IDS: OnceLock<AtomicU32> = OnceLock::new();
    let ids = IDS.get_or_init(|| {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .subsec_nanos();
        AtomicU32::new(nanos ^ std::process::id().rotate_left(16))
    });
    loop {
        let id = ids.fetch_add(1, Ordering::Relaxed);
        if id != 0 {
            return id;
        }
    }
}

pub(crate) fn is_placeholder(symbol: &str) -> bool {
    symbol.starts_with(PLACEHOLDER)
}

pub(crate) fn cell_id(cell: &Cell) -> Option<u32> {
    let mut chars = cell.symbol().chars();
    if chars.next()? != PLACEHOLDER {
        return None;
    }
    chars.next()?;
    chars.next()?;
    let high_mark = chars.next()?;
    let high = DIACRITICS.iter().position(|mark| *mark == high_mark)?;
    let Color::Rgb(r, g, b) = cell.fg else {
        return None;
    };
    Some(u32::from_be_bytes([u8::try_from(high).ok()?, r, g, b]))
}

pub(crate) fn visible_ids(buffer: &Buffer) -> HashSet<u32> {
    buffer.content.iter().filter_map(cell_id).collect()
}

fn mark(cell: &mut Cell, id: u32, row: u16, col: u16) {
    let [high, r, g, b] = id.to_be_bytes();
    let symbol: String = [
        PLACEHOLDER,
        DIACRITICS[usize::from(row)],
        DIACRITICS[usize::from(col)],
        DIACRITICS[usize::from(high)],
    ]
    .into_iter()
    .collect();
    let background = cell.bg;
    cell.reset();
    cell.set_symbol(&symbol)
        .set_fg(Color::Rgb(r, g, b))
        .set_bg(background)
        .set_diff_option(CellDiffOption::ForcedWidth(NonZeroU16::MIN));
}

// Applying text styles must not change the colors that encode image identity.
pub(crate) fn restore_identity(cell: &mut Cell, foreground: Color) {
    cell.fg = foreground;
    cell.modifier
        .remove(Modifier::REVERSED | Modifier::HIDDEN | Modifier::DIM);
    cell.underline_color = Color::Reset;
}

impl Images {
    pub(crate) fn configure(&mut self, config: Config) -> io::Result<()> {
        if config.cell_width == 0
            || config.cell_height == 0
            || config.cell_width > 1024
            || config.cell_height > 1024
        {
            return Err(io::Error::other(
                "image cell dimensions must be between 1 and 1024 pixels",
            ));
        }
        if self.config != config {
            for entry in self.entries.values() {
                if entry.uploaded {
                    self.retired.push((entry.id, self.config.tmux));
                }
            }
            self.entries.clear();
            self.config = config;
        }
        Ok(())
    }

    pub(crate) fn begin(&mut self) {
        self.generation = self.generation.wrapping_add(1);
    }

    fn room(&mut self, cost: u64) -> Result<(), String> {
        while self.entries.len() >= MAX_ENTRIES
            || self.entries.values().map(|entry| entry.cost).sum::<u64>() + cost > CACHE_BUDGET
        {
            let oldest = self
                .entries
                .iter()
                .filter(|(_, entry)| entry.seen != self.generation)
                .min_by_key(|(_, entry)| entry.seen)
                .map(|(_, entry)| entry.id);
            let Some(id) = oldest else {
                return Err("visible images exceed the 64 MiB image cache".into());
            };
            self.entries.retain(|_, entry| {
                if entry.id == id && entry.uploaded {
                    self.retired.push((id, self.config.tmux));
                }
                entry.id != id
            });
        }
        Ok(())
    }

    pub(crate) fn draw(
        &mut self,
        buffer: &mut Buffer,
        source: &Source,
        rect: (i64, i64, u16, u16),
        clip: Rect,
        options: Options,
        cached_only: bool,
    ) -> Result<bool, String> {
        let (x, y, cols, rows) = rect;
        if usize::from(cols) > DIACRITICS.len() || usize::from(rows) > DIACRITICS.len() {
            return Err("image placements support at most 297 columns and rows".into());
        }
        let width = u32::from(cols) * u32::from(self.config.cell_width);
        let height = u32::from(rows) * u32::from(self.config.cell_height);
        if u64::from(width) * u64::from(height) > 4 * 1024 * 1024 {
            return Err("image placement exceeds 4 megapixels".into());
        }
        // Budget decoded output and a conservative PNG encoding bound.
        let cost = u64::from(width) * u64::from(height) * 8 + 1024;
        let key = Key {
            source: source.id,
            options,
            cols,
            rows,
            cell_width: self.config.cell_width,
            cell_height: self.config.cell_height,
        };
        if !self.entries.contains_key(&key) {
            if cached_only {
                return Ok(false);
            }
            self.room(cost)?;
            let prepared = match Prepared::new(source, key.options, width, height) {
                Err(error) if error.starts_with("image worker is busy") => return Ok(false),
                result => result?,
            };
            self.entries.insert(
                key.clone(),
                Entry {
                    id: next_id(),
                    prepared,
                    seen: self.generation,
                    cost,
                    uploaded: false,
                },
            );
        }
        self.draw_entry(buffer, &key, x, y, clip)
    }

    fn draw_entry(
        &mut self,
        buffer: &mut Buffer,
        key: &Key,
        x: i64,
        y: i64,
        clip: Rect,
    ) -> Result<bool, String> {
        let Some(entry) = self.entries.get_mut(key) else {
            return Ok(false);
        };
        entry.seen = self.generation;
        match entry.prepared.get() {
            None => return Ok(false),
            Some(Err(error)) => return Err(error.clone()),
            Some(Ok(_)) => {}
        }
        for row in clip.top()..clip.bottom() {
            for col in clip.left()..clip.right() {
                let source_row =
                    u16::try_from(i64::from(row) - y).map_err(|error| error.to_string())?;
                let source_col =
                    u16::try_from(i64::from(col) - x).map_err(|error| error.to_string())?;
                if source_row < key.rows
                    && source_col < key.cols
                    && let Some(cell) = buffer.cell_mut((col, row))
                {
                    mark(cell, entry.id, source_row, source_col);
                }
            }
        }
        Ok(true)
    }

    pub(crate) fn present(
        &mut self,
        visible: &HashSet<u32>,
        out: &mut impl Write,
    ) -> io::Result<()> {
        for &(id, tmux) in &self.retired {
            delete(out, id, tmux)?;
        }
        self.retired.clear();
        for (key, entry) in &mut self.entries {
            if !visible.contains(&entry.id) {
                continue;
            }
            if entry.uploaded {
                continue;
            }
            if let Some(Ok(data)) = entry.prepared.get() {
                transmit(out, entry.id, key.cols, key.rows, data, self.config.tmux)?;
                entry.uploaded = true;
            }
        }
        Ok(())
    }

    pub(crate) fn reset(&mut self, out: &mut impl Write) -> io::Result<()> {
        for &(id, tmux) in &self.retired {
            delete(out, id, tmux)?;
        }
        self.retired.clear();
        for entry in self.entries.values_mut() {
            if entry.uploaded {
                delete(out, entry.id, self.config.tmux)?;
                entry.uploaded = false;
            }
        }
        Ok(())
    }

    pub(crate) fn invalidate(&mut self) {
        for entry in self.entries.values_mut() {
            entry.uploaded = false;
        }
    }
}

fn command(out: &mut impl Write, control: &str, payload: &str, tmux: bool) -> io::Result<()> {
    if tmux {
        write!(out, "\x1bPtmux;\x1b")?;
    }
    write!(out, "\x1b_G{control};{payload}")?;
    if tmux {
        write!(out, "\x1b")?;
    }
    write!(out, "\x1b\\")?;
    if tmux {
        write!(out, "\x1b\\")?;
    }
    Ok(())
}

fn delete(out: &mut impl Write, id: u32, tmux: bool) -> io::Result<()> {
    command(out, &format!("a=d,d=I,i={id},q=2"), "", tmux)
}

fn transmit(
    out: &mut impl Write,
    id: u32,
    cols: u16,
    rows: u16,
    data: &super::transform::Encoded,
    tmux: bool,
) -> io::Result<()> {
    let chunks = data.png.chunks(3072);
    let count = chunks.len();
    for (index, chunk) in chunks.enumerate() {
        let more = u8::from(index + 1 != count);
        let control = if index == 0 {
            format!(
                "a=T,U=1,f=100,t=d,q=2,i={id},c={cols},r={rows},s={},v={},m={more}",
                data.width, data.height
            )
        } else {
            format!("q=2,m={more}")
        };
        command(out, &control, &STANDARD.encode(chunk), tmux)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn configured() -> Images {
        Images {
            config: Config {
                protocol: Protocol::Kitty,
                cell_width: 1,
                cell_height: 1,
                tmux: false,
            },
            ..Images::default()
        }
    }

    fn source() -> Source {
        Source::rgba(2, 1, &[255, 0, 0, 255, 0, 0, 255, 255]).unwrap()
    }

    fn draw(
        images: &mut Images,
        buffer: &mut Buffer,
        source: &Source,
        rect: (i64, i64, u16, u16),
        clip: Rect,
        options: Options,
    ) {
        let start = Instant::now();
        loop {
            if images
                .draw(buffer, source, rect, clip, options, false)
                .unwrap()
            {
                break;
            }
            assert!(
                start.elapsed() < Duration::from_secs(5),
                "image did not prepare"
            );
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    #[test]
    fn clipping_keeps_original_image_coordinates() {
        let mut images = configured();
        let mut buffer = Buffer::empty(Rect::new(0, 0, 4, 3));
        let source = source();
        draw(
            &mut images,
            &mut buffer,
            &source,
            (-2, -1, 4, 3),
            Rect::new(0, 0, 2, 2),
            Options::default(),
        );
        let marks: Vec<_> = buffer[(0, 0)].symbol().chars().collect();
        assert_eq!(marks[1], DIACRITICS[1]);
        assert_eq!(marks[2], DIACRITICS[2]);
        assert_eq!(buffer[(2, 0)].symbol(), " ");
        assert_eq!(buffer[(0, 2)].symbol(), " ");
        assert_eq!(
            buffer[(0, 0)].diff_option,
            CellDiffOption::ForcedWidth(NonZeroU16::MIN)
        );
    }

    #[test]
    fn only_final_visible_cells_trigger_upload_and_reuse() {
        let mut images = configured();
        let area = Rect::new(0, 0, 4, 2);
        let mut buffer = Buffer::empty(area);
        let source = source();
        draw(
            &mut images,
            &mut buffer,
            &source,
            (0, 0, 4, 2),
            area,
            Options::default(),
        );
        buffer.reset(); // a later opaque view covered the entire image
        let mut output = Vec::new();
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        assert!(output.is_empty());
        draw(
            &mut images,
            &mut buffer,
            &source,
            (0, 0, 4, 2),
            area,
            Options::default(),
        );
        buffer[(0, 0)].reset(); // first cell covered, remaining cells still visible
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        assert!(String::from_utf8_lossy(&output).contains("a=T,U=1,f=100,t=d,q=2"));
        output.clear();
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        assert!(output.is_empty());
    }

    #[test]
    fn views_share_only_identical_transforms_and_reset_reuploads() {
        let mut images = configured();
        let area = Rect::new(0, 0, 2, 1);
        let mut buffer = Buffer::empty(area);
        let source = source();
        draw(
            &mut images,
            &mut buffer,
            &source,
            (0, 0, 2, 1),
            area,
            Options::default(),
        );
        let first = cell_id(&buffer[(0, 0)]).unwrap();
        let mut output = Vec::new();
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        let rotated = Options {
            rotation: 180,
            ..Options::default()
        };
        draw(
            &mut images,
            &mut buffer,
            &source,
            (0, 0, 2, 1),
            area,
            rotated,
        );
        let second = cell_id(&buffer[(0, 0)]).unwrap();
        assert_ne!(first, second);
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        output.clear();
        images.reset(&mut output).unwrap();
        let deleted = String::from_utf8(output.clone()).unwrap();
        assert!(deleted.contains(&format!("a=d,d=I,i={first},q=2")));
        assert!(deleted.contains(&format!("a=d,d=I,i={second},q=2")));
        assert!(!deleted.contains("d=A"));
        output.clear();
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        assert!(!output.is_empty());
    }

    #[test]
    fn protocol_chunks_are_bounded_and_preserve_payload() {
        let data = super::super::transform::Encoded {
            png: (0_u8..=255).cycle().take(12000).collect(),
            width: 20,
            height: 10,
        };
        let mut output = Vec::new();
        transmit(&mut output, 42, 4, 2, &data, false).unwrap();
        let wire = String::from_utf8(output).unwrap();
        let mut decoded = Vec::new();
        for command in wire.split("\x1b_G").skip(1) {
            let (header, rest) = command.split_once(';').unwrap();
            let payload = rest.strip_suffix("\x1b\\").unwrap();
            assert!(payload.len() <= 4096);
            assert!(header.contains("q=2"));
            decoded.extend(STANDARD.decode(payload).unwrap());
        }
        assert_eq!(decoded, data.png);
        assert!(wire.contains("q=2,m=0;"));
    }

    #[test]
    fn tmux_passthrough_escapes_both_terminators() {
        let mut out = Vec::new();
        delete(&mut out, 42, true).unwrap();
        assert_eq!(
            out,
            b"\x1bPtmux;\x1b\x1b_Ga=d,d=I,i=42,q=2;\x1b\x1b\\\x1b\\"
        );
    }

    #[test]
    fn failed_transmission_is_retried() {
        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                Err(io::Error::other("broken"))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut images = configured();
        let area = Rect::new(0, 0, 2, 1);
        let mut buffer = Buffer::empty(area);
        draw(
            &mut images,
            &mut buffer,
            &source(),
            (0, 0, 2, 1),
            area,
            Options::default(),
        );
        assert!(images.present(&visible_ids(&buffer), &mut Broken).is_err());
        let mut output = Vec::new();
        images.present(&visible_ids(&buffer), &mut output).unwrap();
        assert!(!output.is_empty());
    }

    #[test]
    fn cached_redraw_never_starts_work_or_resurrects_an_evicted_variant() {
        let mut images = configured();
        let area = Rect::new(0, 0, 2, 1);
        let mut buffer = Buffer::empty(area);
        let source = source();
        assert!(
            !images
                .draw(
                    &mut buffer,
                    &source,
                    (0, 0, 2, 1),
                    area,
                    Options::default(),
                    true
                )
                .unwrap()
        );
        assert!(images.entries.is_empty());
        draw(
            &mut images,
            &mut buffer,
            &source,
            (0, 0, 2, 1),
            area,
            Options::default(),
        );
        let id = cell_id(&buffer[(0, 0)]);
        buffer.reset();
        assert!(
            images
                .draw(
                    &mut buffer,
                    &source,
                    (0, 0, 2, 1),
                    area,
                    Options::default(),
                    true
                )
                .unwrap()
        );
        assert_eq!(cell_id(&buffer[(0, 0)]), id);
        images.entries.clear();
        assert!(
            !images
                .draw(
                    &mut buffer,
                    &source,
                    (0, 0, 2, 1),
                    area,
                    Options::default(),
                    true
                )
                .unwrap()
        );
        assert!(images.entries.is_empty());
    }
}
