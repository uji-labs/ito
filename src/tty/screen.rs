use std::io;

use mlua::{Function, UserData, UserDataMethods, Value};
use ratatui::layout::Rect;
use ratatui::style::Style;

mod area;
mod read;
mod style;
mod targets;

pub(crate) use read::row_text;

use crate::convert;

use super::surface::{Cursor, Shape, Surface};
use area::{Area, region};
use read::{Run, runs};
use style::StyleSpec;
use targets::Targets;

pub struct Screen {
    surface: Box<dyn Surface>,
    styles: Vec<Style>,
    cursor: Option<Cursor>,
    targets: Targets,
}

impl Screen {
    pub(crate) fn new(surface: Box<dyn Surface>) -> Self {
        Self {
            surface,
            styles: Vec::new(),
            cursor: None,
            targets: Targets::default(),
        }
    }

    #[must_use]
    pub fn forget(mut self) -> Self {
        self.targets.clear();
        self
    }

    fn resolve(&self, id: Option<usize>) -> io::Result<Style> {
        match id {
            None | Some(0) => Ok(Style::default()),
            Some(id) => self
                .styles
                .get(id.saturating_sub(1))
                .copied()
                .ok_or_else(|| io::Error::other(format!("unknown style {id}"))),
        }
    }

    fn put(&mut self, at: (u16, u16), right: u16, text: &str, style: Style) -> u16 {
        let (col, row) = at;
        if col >= right {
            return col;
        }
        let limit = usize::from(right.saturating_sub(col));
        self.surface
            .buffer()
            .set_stringn(col, row, text, limit, style)
            .0
    }

    fn span(&mut self, at: (u16, u16), right: u16, span: Value) -> mlua::Result<u16> {
        let (text, style) = match span {
            Value::String(text) => (text, Style::default()),
            Value::Table(span) => (
                span.raw_get::<mlua::LuaString>(1)?,
                self.resolve(span.raw_get(2)?)?,
            ),
            other => {
                return Err(io::Error::other(format!(
                    "a span is a string or a table, not a {}",
                    other.type_name()
                ))
                .into());
            }
        };
        Ok(self.put(at, right, &String::from_utf8_lossy(&text.as_bytes()), style))
    }

    fn cover(&mut self, area: Rect, style: Style, symbol: &str) {
        let area = area.intersection(self.surface.buffer().area);
        self.targets.record(area, None);
        let buffer = self.surface.buffer();
        for row in area.top()..area.bottom() {
            for col in area.left()..area.right() {
                if let Some(cell) = buffer.cell_mut((col, row)) {
                    cell.reset();
                    cell.set_symbol(symbol);
                    cell.set_style(style);
                }
            }
        }
    }
}

impl Screen {
    fn size(&mut self) -> io::Result<(u16, u16)> {
        self.surface.size()
    }

    fn style(&mut self, spec: &StyleSpec) -> io::Result<usize> {
        self.styles.push(spec.style()?);
        Ok(self.styles.len())
    }

    fn line(&mut self, row: i64, col: i64, spans: Value, width: Option<i64>) -> mlua::Result<i64> {
        let area = self.surface.buffer().area;
        let (Ok(top), Ok(left)) = (u16::try_from(row), u16::try_from(col)) else {
            return Ok(col);
        };
        if top >= area.height {
            return Ok(col);
        }
        let right = width.map_or(area.width, |width| {
            region(row, col, width, 1).right().min(area.width)
        });
        let on_click = match &spans {
            Value::Table(spans) => spans.raw_get("on_click")?,
            _ => None,
        };
        self.targets.record(
            Rect::new(left, top, right.saturating_sub(left), 1),
            on_click,
        );
        let end = match spans {
            Value::Nil => Ok(left),
            Value::String(_) => self.span((left, top), right, spans),
            Value::Table(spans) => spans
                .sequence_values::<Value>()
                .try_fold(left, |at, span| self.span((at, top), right, span?)),
            other => Err(io::Error::other(format!(
                "a line is a string or a list of spans, not a {}",
                other.type_name()
            ))
            .into()),
        };
        end.map(i64::from)
    }

    fn fill(&mut self, area: &Area, style: Option<usize>, symbol: Option<&str>) -> io::Result<()> {
        let style = self.resolve(style)?;
        self.cover(area.rect(), style, symbol.unwrap_or(" "));
        Ok(())
    }

    fn paint(&mut self, area: &Area, style: usize) -> io::Result<()> {
        let style = self.resolve(Some(style))?;
        let buffer = self.surface.buffer();
        let area = area.rect().intersection(buffer.area);
        buffer.set_style(area, style);
        Ok(())
    }

    fn text(&mut self, row: i64) -> Option<String> {
        let buffer = self.surface.buffer();
        u16::try_from(row)
            .ok()
            .filter(|row| *row < buffer.area.height)
            .map(|row| row_text(buffer, row))
    }

    fn spans(&mut self, row: i64) -> Option<Vec<Run>> {
        let buffer = self.surface.buffer();
        u16::try_from(row)
            .ok()
            .filter(|row| *row < buffer.area.height)
            .map(|row| runs(buffer, row))
    }

    fn clear(&mut self) {
        self.surface.buffer().reset();
        self.targets.clear();
    }

    fn clicked(&mut self, row: i64, col: i64) -> Option<Function> {
        self.targets.at(row, col)
    }

    fn cursor(&mut self, row: Option<i64>, col: Option<i64>, name: Option<&str>) -> io::Result<()> {
        let at = row
            .and_then(|row| u16::try_from(row).ok())
            .zip(col.and_then(|col| u16::try_from(col).ok()));
        self.cursor = match at {
            Some((row, col)) => Some(Cursor {
                row,
                col,
                shape: Shape::named(name)?,
            }),
            None => None,
        };
        Ok(())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.targets.flushed();
        self.surface.present(self.cursor)
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.surface.write(bytes)
    }

    fn suspend(&mut self) -> io::Result<()> {
        self.surface.suspend()
    }

    fn resume(&mut self) -> io::Result<()> {
        self.surface.resume()
    }

    fn close(&mut self) -> io::Result<()> {
        self.surface.close()
    }
}

fn raised(err: io::Error) -> mlua::Error {
    mlua::Error::external(err)
}

impl UserData for Screen {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("size", |_, screen, ()| screen.size().map_err(raised));
        methods.add_method_mut("style", |lua, screen, spec: Value| {
            let spec: StyleSpec = convert::options(lua, spec)?;
            screen.style(&spec).map_err(raised)
        });
        methods.add_method_mut(
            "line",
            |_, screen, (row, col, spans, width): (i64, i64, Value, Option<i64>)| {
                screen.line(row, col, spans, width)
            },
        );
        methods.add_method_mut(
            "fill",
            |lua, screen, (area, style, symbol): (Value, Option<usize>, Option<String>)| {
                let area: Area = convert::options(lua, area)?;
                screen.fill(&area, style, symbol.as_deref()).map_err(raised)
            },
        );
        methods.add_method_mut("paint", |lua, screen, (area, style): (Value, usize)| {
            let area: Area = convert::options(lua, area)?;
            screen.paint(&area, style).map_err(raised)
        });
        methods.add_method_mut("text", |_, screen, row: i64| Ok(screen.text(row)));
        methods.add_method_mut("spans", |lua, screen, row: i64| match screen.spans(row) {
            Some(runs) => convert::value(lua, &runs),
            None => Ok(Value::Nil),
        });
        methods.add_method_mut("clear", |_, screen, ()| {
            screen.clear();
            Ok(())
        });
        methods.add_method_mut("clicked", |_, screen, (row, col): (i64, i64)| {
            Ok(screen.clicked(row, col))
        });
        methods.add_method_mut(
            "cursor",
            |_, screen, (row, col, name): (Option<i64>, Option<i64>, Option<String>)| {
                screen.cursor(row, col, name.as_deref()).map_err(raised)
            },
        );
        methods.add_method_mut("flush", |_, screen, ()| screen.flush().map_err(raised));
        methods.add_method_mut("write", |_, screen, bytes: mlua::LuaString| {
            screen.write(&bytes.as_bytes()).map_err(raised)
        });
        methods.add_method_mut("suspend", |_, screen, ()| screen.suspend().map_err(raised));
        methods.add_method_mut("resume", |_, screen, ()| screen.resume().map_err(raised));
        methods.add_method_mut("close", |_, screen, ()| screen.close().map_err(raised));
    }
}
