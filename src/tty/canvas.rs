//! Styled cell frames for the browser Canvas renderer in `web/canvas.js`.

use std::cell::Cell as Value;
use std::io;
use std::rc::Rc;

use ratatui::buffer::{Buffer, CellWidth};
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier};
use serde::Serialize;
use tokio::sync::mpsc;

use super::event::Event;
use super::surface::{Cursor, Shape, Surface};
use super::{Input, Screen, Terminal};
use crate::image::kitty::Images;

#[derive(Debug, Serialize)]
pub struct Cell {
    pub row: u16,
    pub col: u16,
    pub width: u16,
    pub text: String,
    pub fg: Option<String>,
    pub bg: Option<String>,
    pub modifiers: Vec<&'static str>,
    pub link: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct Caret {
    pub row: u16,
    pub col: u16,
    pub shape: &'static str,
}

#[derive(Debug, Serialize)]
pub struct Frame {
    pub width: u16,
    pub height: u16,
    pub cells: Vec<Cell>,
    pub cursor: Option<Caret>,
}

pub struct Handle {
    size: Rc<Value<(u16, u16)>>,
    events: mpsc::UnboundedSender<Event>,
}

impl Handle {
    pub fn send(&self, event: Event) -> bool {
        self.events.send(event).is_ok()
    }

    pub fn resize(&self, width: u16, height: u16) -> bool {
        self.size.set((width, height));
        self.send(Event::Resize { width, height })
    }
}

struct Canvas<F> {
    buffer: Buffer,
    size: Rc<Value<(u16, u16)>>,
    present: F,
}

// The 16 ANSI colours every terminal agrees on.
const PALETTE: [u32; 16] = [
    0x00_00_00, 0x80_00_00, 0x00_80_00, 0x80_80_00, 0x00_00_80, 0x80_00_80, 0x00_80_80, 0xc0_c0_c0,
    0x80_80_80, 0xff_00_00, 0x00_ff_00, 0xff_ff_00, 0x00_00_ff, 0xff_00_ff, 0x00_ff_ff, 0xff_ff_ff,
];

// xterm adds a 6×6×6 cube and 24 greys above those.
fn indexed(index: u8) -> u32 {
    match index {
        0..=15 => PALETTE[usize::from(index)],
        16..=231 => {
            let index = u32::from(index - 16);
            let level = |value| if value == 0 { 0 } else { 55 + value * 40 };
            (level(index / 36) << 16) | (level(index / 6 % 6) << 8) | level(index % 6)
        }
        grey => {
            let level = u32::from(8 + (grey - 232) * 10);
            level * 0x01_01_01
        }
    }
}

fn color(color: Color) -> Option<String> {
    let rgb = match color {
        Color::Reset => return None,
        Color::Black => PALETTE[0],
        Color::Red => PALETTE[1],
        Color::Green => PALETTE[2],
        Color::Yellow => PALETTE[3],
        Color::Blue => PALETTE[4],
        Color::Magenta => PALETTE[5],
        Color::Cyan => PALETTE[6],
        Color::Gray => PALETTE[7],
        Color::DarkGray => PALETTE[8],
        Color::LightRed => PALETTE[9],
        Color::LightGreen => PALETTE[10],
        Color::LightYellow => PALETTE[11],
        Color::LightBlue => PALETTE[12],
        Color::LightMagenta => PALETTE[13],
        Color::LightCyan => PALETTE[14],
        Color::White => PALETTE[15],
        Color::Rgb(red, green, blue) => {
            (u32::from(red) << 16) | (u32::from(green) << 8) | u32::from(blue)
        }
        Color::Indexed(index) => indexed(index),
    };
    Some(format!("#{rgb:06x}"))
}

fn modifiers(cell: &ratatui::buffer::Cell) -> Vec<&'static str> {
    [
        ("bold", Modifier::BOLD),
        ("dim", Modifier::DIM),
        ("italic", Modifier::ITALIC),
        ("underline", Modifier::UNDERLINED),
        ("reverse", Modifier::REVERSED),
        ("strikethrough", Modifier::CROSSED_OUT),
        ("hidden", Modifier::HIDDEN),
        ("blink", Modifier::SLOW_BLINK | Modifier::RAPID_BLINK),
    ]
    .into_iter()
    .filter_map(|(name, flag)| cell.modifier.intersects(flag).then_some(name))
    .collect()
}

fn snapshot(buffer: &Buffer, cursor: Option<Cursor>) -> Frame {
    let mut cells = Vec::new();
    for row in 0..buffer.area.height {
        let mut col = 0;
        while col < buffer.area.width {
            let cell = &buffer[(col, row)];
            let width = cell.cell_width().max(1).min(buffer.area.width - col);
            let (link, text) = super::screen::cell_contents(cell.symbol());
            cells.push(Cell {
                row,
                col,
                width,
                text: text.to_string(),
                fg: color(cell.fg),
                bg: color(cell.bg),
                modifiers: modifiers(cell),
                link: link.map(str::to_string),
            });
            col += width;
        }
    }
    Frame {
        width: buffer.area.width,
        height: buffer.area.height,
        cells,
        cursor: cursor.map(|cursor| Caret {
            row: cursor.row,
            col: cursor.col,
            shape: match cursor.shape {
                Shape::Block => "block",
                Shape::Bar => "bar",
                Shape::Underline => "underline",
            },
        }),
    }
}

impl<F: FnMut(Frame) -> io::Result<()>> Surface for Canvas<F> {
    fn buffer(&mut self) -> &mut Buffer {
        &mut self.buffer
    }

    fn size(&mut self) -> io::Result<(u16, u16)> {
        let (width, height) = self.size.get();
        let area = Rect::new(0, 0, width, height);
        if self.buffer.area != area {
            self.buffer.resize(area);
        }
        Ok((width, height))
    }

    fn present(&mut self, cursor: Option<Cursor>, images: &mut Images) -> io::Result<()> {
        // Cells are all a Canvas can paint, so kitty images are dropped instead
        // of uploaded. Their placeholder cells read as blank.
        images.reset(&mut io::sink())?;
        (self.present)(snapshot(&self.buffer, cursor))
    }

    fn reset_images(&mut self, images: &mut Images) -> io::Result<()> {
        images.reset(&mut io::sink())
    }

    fn write(&mut self, _bytes: &[u8]) -> io::Result<()> {
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "Canvas does not interpret raw terminal escape sequences",
        ))
    }

    fn suspend(&mut self) -> io::Result<()> {
        Ok(())
    }
    fn resume(&mut self) -> io::Result<()> {
        Ok(())
    }
    fn close(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// Create a terminal whose flushes publish styled frames to `present`.
/// Feed browser events through the handle and consume them with `input:poll()`.
pub fn terminal(
    width: u16,
    height: u16,
    present: impl FnMut(Frame) -> io::Result<()> + 'static,
) -> (Terminal, Handle) {
    let size = Rc::new(Value::new((width, height)));
    let (sender, events) = mpsc::unbounded_channel();
    let surface = Canvas {
        buffer: Buffer::empty(Rect::new(0, 0, width, height)),
        size: Rc::clone(&size),
        present,
    };
    (
        Terminal::Open(Screen::new(Box::new(surface)), Input::new(events, None)),
        Handle {
            size,
            events: sender,
        },
    )
}
