use std::io;

use ratatui::buffer::Buffer;

#[derive(Clone, Copy)]
pub(crate) enum Shape {
    Block,
    Bar,
    Underline,
}

impl Shape {
    pub(crate) fn named(name: Option<&str>) -> io::Result<Self> {
        match name {
            None | Some("block") => Ok(Self::Block),
            Some("bar") => Ok(Self::Bar),
            Some("underline") => Ok(Self::Underline),
            Some(other) => Err(io::Error::other(format!("unknown cursor shape {other}"))),
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) struct Cursor {
    pub(crate) row: u16,
    pub(crate) col: u16,
    pub(crate) shape: Shape,
}

pub(crate) trait Surface {
    fn buffer(&mut self) -> &mut Buffer;
    fn size(&mut self) -> io::Result<(u16, u16)>;
    fn present(&mut self, cursor: Option<Cursor>) -> io::Result<()>;
    fn write(&mut self, bytes: &[u8]) -> io::Result<()>;
    fn suspend(&mut self) -> io::Result<()>;
    fn resume(&mut self) -> io::Result<()>;
    fn close(&mut self) -> io::Result<()>;
}
