use ratatui::layout::Rect;

#[derive(serde::Deserialize)]
pub(super) struct Area {
    x: i64,
    y: i64,
    width: i64,
    height: i64,
}

impl Area {
    pub(super) fn rect(&self) -> Rect {
        region(self.y, self.x, self.width, self.height)
    }
}

pub(super) fn region(row: i64, col: i64, width: i64, height: i64) -> Rect {
    let fit = |value: i64| u16::try_from(value.clamp(0, i64::from(u16::MAX))).unwrap_or(u16::MAX);
    let (top, left) = (fit(row), fit(col));
    let (bottom, right) = (
        fit(row.saturating_add(height)),
        fit(col.saturating_add(width)),
    );
    Rect::new(
        left,
        top,
        right.saturating_sub(left),
        bottom.saturating_sub(top),
    )
}
