use mlua::Function;
use ratatui::layout::{Position, Rect};

struct Target {
    area: Rect,
    on_click: Option<Function>,
}

#[derive(Default)]
pub(super) struct Targets {
    drawn: Vec<Target>,
    flushed: bool,
}

impl Targets {
    pub(super) fn record(&mut self, area: Rect, on_click: Option<Function>) {
        if self.flushed {
            self.flushed = false;
            self.drawn.clear();
        }
        self.drawn.push(Target { area, on_click });
    }

    pub(super) fn flushed(&mut self) {
        self.flushed = true;
    }

    pub(super) fn clear(&mut self) {
        self.drawn.clear();
        self.flushed = false;
    }

    pub(super) fn at(&self, row: i64, col: i64) -> Option<Function> {
        let at = Position::new(u16::try_from(col).ok()?, u16::try_from(row).ok()?);
        self.drawn
            .iter()
            .rev()
            .find(|target| target.area.contains(at))?
            .on_click
            .clone()
    }
}
