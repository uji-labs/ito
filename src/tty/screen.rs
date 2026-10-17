use std::collections::HashMap;
use std::io;

use mlua::{AnyUserData, Function, LuaString, UserData, UserDataMethods, Value};
use ratatui::layout::Rect;
use ratatui::style::Style;

mod area;
mod link;
mod read;
mod style;
mod targets;

pub(crate) use read::row_text;

#[cfg(feature = "canvas")]
pub(super) fn cell_contents(symbol: &str) -> (Option<&str>, &str) {
    Link::split(symbol)
}

use crate::convert;
use crate::image::{
    Options, Phase, Source,
    kitty::{self, Config, Images, Protocol, Setup},
};

use super::surface::{Cursor, Shape, Surface};
use area::{Area, region};
use link::Link;
use read::{Run, runs};
use style::text_style;
use targets::Targets;

pub struct Screen {
    surface: Box<dyn Surface>,
    styles: HashMap<usize, Style>,
    cursor: Option<Cursor>,
    targets: Targets,
    images: Box<Images>,
}

impl Screen {
    pub(crate) fn new(surface: Box<dyn Surface>) -> Self {
        Self {
            surface,
            styles: HashMap::new(),
            cursor: None,
            targets: Targets::default(),
            images: Box::default(),
        }
    }

    #[must_use]
    pub fn forget(mut self) -> Self {
        let config = self.images.config;
        let _ = self.surface.reset_images(&mut self.images);
        self.images = Box::default();
        self.images.config = config;
        self.targets.clear();
        self.styles.clear();
        self
    }

    fn resolve(&mut self, style: &Value) -> mlua::Result<Style> {
        let style = match style {
            Value::Nil => return Ok(Style::default()),
            Value::Table(style) => style,
            Value::Integer(_) | Value::Number(_) => {
                return Err(io::Error::other("a style is an ito.TextStyle, not a number").into());
            }
            other => {
                return Err(io::Error::other(format!(
                    "a style is an ito.TextStyle, not a {}",
                    other.type_name()
                ))
                .into());
            }
        };
        let address = style.to_pointer() as usize;
        if let Some(found) = self.styles.get(&address) {
            return Ok(*found);
        }
        let found = text_style(style)?;
        self.styles.insert(address, found);
        Ok(found)
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
        let (text, style, link) = match span {
            Value::String(text) => (text, Style::default(), None),
            Value::Table(span) => (
                span.raw_get::<LuaString>(1)?,
                self.resolve(&span.raw_get::<Value>(2)?)?,
                span.raw_get::<Option<String>>("link")?,
            ),
            other => {
                return Err(io::Error::other(format!(
                    "a span is a string or a table, not a {}",
                    other.type_name()
                ))
                .into());
            }
        };
        let link = link.as_deref().map(Link::new).transpose()?;
        let end = self.put(at, right, &String::from_utf8_lossy(&text.as_bytes()), style);
        Link::apply(link.as_ref(), self.surface.buffer(), at.1, at.0, end);
        Ok(end)
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
        if self.images.config.auto
            && self.images.config.protocol == Protocol::Kitty
            && let Some((cell_width, cell_height)) = self.surface.cell_size()
        {
            self.images.configure(Config {
                cell_width,
                cell_height,
                ..self.images.config
            })?;
        }
        self.surface.size()
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

    fn fill(&mut self, area: &Area, style: &Value, symbol: Option<&str>) -> mlua::Result<()> {
        let style = self.resolve(style)?;
        self.cover(area.rect(), style, symbol.unwrap_or(" "));
        Ok(())
    }

    fn paint(&mut self, area: &Area, style: &Value) -> mlua::Result<()> {
        if style.is_nil() {
            return Err(io::Error::other("paint needs an ito.TextStyle").into());
        }
        let style = self.resolve(style)?;
        let buffer = self.surface.buffer();
        let area = area.rect().intersection(buffer.area);
        for row in area.top()..area.bottom() {
            for col in area.left()..area.right() {
                let cell = &mut buffer[(col, row)];
                let image = kitty::is_placeholder(cell.symbol());
                let foreground = cell.fg;
                cell.set_style(style);
                if image {
                    kitty::restore_identity(cell, foreground);
                }
            }
        }
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
        self.images.begin();
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
        self.styles.clear();
        let result = self.surface.present(self.cursor, &mut self.images);
        if result.is_err() {
            self.images.invalidate();
        }
        result
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.surface.write(bytes)
    }

    fn suspend(&mut self) -> io::Result<()> {
        let images = self.surface.reset_images(&mut self.images);
        let terminal = self.surface.suspend();
        images.and(terminal)
    }

    fn resume(&mut self) -> io::Result<()> {
        self.images.invalidate();
        self.surface.resume()
    }

    fn close(&mut self) -> io::Result<()> {
        let images = self.surface.reset_images(&mut self.images);
        let terminal = self.surface.close();
        images.and(terminal)
    }

    fn setup_images(&mut self, setup: Setup) -> io::Result<()> {
        self.images
            .configure(setup.config().map_err(io::Error::other)?)?;
        self.size()?;
        Ok(())
    }

    fn image(
        &mut self,
        source: &Source,
        area: &Area,
        options: Options,
        clip: Option<&Area>,
        cached_only: bool,
    ) -> Phase {
        if self.images.config.protocol == Protocol::Off {
            return Phase::Unsupported;
        }
        match source.pixels() {
            None => return Phase::Loading,
            Some(Err(error)) => return Phase::Failed(error.clone()),
            Some(Ok(_)) => {}
        }
        let bounds = self.surface.buffer().area;
        let placed = match Placement::of(area, clip, bounds) {
            Err(problem) => return Phase::Failed(problem),
            Ok(None) => return Phase::Ready,
            Ok(Some(placed)) => placed,
        };
        match self.images.draw(
            self.surface.buffer(),
            source,
            placed.rect,
            placed.visible,
            options,
            cached_only,
        ) {
            Ok(true) => {
                self.targets.record(placed.visible, None);
                Phase::Ready
            }
            Ok(false) => Phase::Loading,
            Err(problem) => Phase::Failed(problem),
        }
    }
}

// Where an image lands, in cells, and the part of it the screen can show.
struct Placement {
    rect: (i64, i64, u16, u16),
    visible: Rect,
}

impl Placement {
    fn of(area: &Area, clip: Option<&Area>, bounds: Rect) -> Result<Option<Self>, String> {
        let visible = area
            .rect()
            .intersection(clip.map_or(bounds, Area::rect))
            .intersection(bounds);
        if visible.is_empty() {
            return Ok(None);
        }
        let (Ok(width), Ok(height)) = (u16::try_from(area.width), u16::try_from(area.height))
        else {
            return Err("invalid image placement size".into());
        };
        Ok(Some(Self {
            rect: (area.x, area.y, width, height),
            visible,
        }))
    }
}

impl Drop for Screen {
    fn drop(&mut self) {
        let _ = self.surface.reset_images(&mut self.images);
    }
}

fn raised(err: io::Error) -> mlua::Error {
    mlua::Error::external(err)
}

impl UserData for Screen {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("configure_images", |lua, screen, value: Value| {
            let setup: Setup = convert::options(lua, value)?;
            screen.setup_images(setup).map_err(raised)?;
            Ok(())
        });
        methods.add_method("image_capabilities", |lua, screen, ()| {
            convert::value(lua, &screen.images.config)
        });
        methods.add_method_mut(
            "image",
            |lua,
             screen,
             (source, area, options, clip, cached): (
                AnyUserData,
                Value,
                Value,
                Value,
                Option<bool>,
            )| {
                let source = source.borrow::<Source>()?;
                let area: Area = convert::options(lua, area)?;
                let options: Options = convert::options(lua, options)?;
                let clip: Option<Area> = if clip.is_nil() {
                    None
                } else {
                    Some(convert::options(lua, clip)?)
                };
                let phase = screen.image(
                    &source,
                    &area,
                    options,
                    clip.as_ref(),
                    cached.unwrap_or(false),
                );
                let status = lua.create_table()?;
                status.set("phase", phase.name())?;
                if let Some(problem) = phase.error() {
                    status.set("error", problem)?;
                }
                Ok(status)
            },
        );
        methods.add_method_mut("size", |_, screen, ()| screen.size().map_err(raised));
        methods.add_method_mut(
            "line",
            |_, screen, (row, col, spans, width): (i64, i64, Value, Option<i64>)| {
                screen.line(row, col, spans, width)
            },
        );
        methods.add_method_mut(
            "fill",
            |lua, screen, (area, style, symbol): (Value, Value, Option<String>)| {
                let area: Area = convert::options(lua, area)?;
                screen.fill(&area, &style, symbol.as_deref())
            },
        );
        methods.add_method_mut("paint", |lua, screen, (area, style): (Value, Value)| {
            let area: Area = convert::options(lua, area)?;
            screen.paint(&area, &style)
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
        methods.add_method_mut("write", |_, screen, bytes: LuaString| {
            screen.write(&bytes.as_bytes()).map_err(raised)
        });
        methods.add_method_mut("suspend", |_, screen, ()| screen.suspend().map_err(raised));
        methods.add_method_mut("resume", |_, screen, ()| screen.resume().map_err(raised));
        methods.add_method_mut("close", |_, screen, ()| screen.close().map_err(raised));
    }
}
