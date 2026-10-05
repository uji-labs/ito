use std::convert::Infallible;
use std::io;

use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use tokio::sync::watch;

use super::VirtualTerminal;
use super::input::Input;
use super::screen::{Screen, row_text};
use super::surface::{Cursor, Surface};

struct Virtual {
    terminal: Terminal<TestBackend>,
    frames: watch::Sender<Vec<String>>,
    size: watch::Receiver<(u16, u16)>,
}

impl Virtual {
    fn snapshot(&self) -> Vec<String> {
        let buffer = self.terminal.backend().buffer();
        (buffer.area.top()..buffer.area.bottom())
            .map(|row| row_text(buffer, row))
            .collect()
    }
}

impl Surface for Virtual {
    fn buffer(&mut self) -> &mut Buffer {
        self.terminal.current_buffer_mut()
    }

    fn size(&mut self) -> io::Result<(u16, u16)> {
        let (width, height) = *self.size.borrow_and_update();
        let area = self.terminal.current_buffer_mut().area;
        if (area.width, area.height) != (width, height) {
            self.terminal.backend_mut().resize(width, height);
            self.terminal
                .resize(Rect::new(0, 0, width, height))
                .unwrap_or_else(never);
        }
        Ok((width, height))
    }

    fn present(&mut self, _cursor: Option<Cursor>) -> io::Result<()> {
        self.terminal.flush().unwrap_or_else(never);
        self.terminal.swap_buffers();
        self.frames.send_replace(self.snapshot());
        Ok(())
    }

    fn write(&mut self, _bytes: &[u8]) -> io::Result<()> {
        Ok(())
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

fn never<T>(impossible: Infallible) -> T {
    match impossible {}
}

pub(crate) fn open(terminal: VirtualTerminal) -> (Screen, Input) {
    let (width, height) = *terminal.size.borrow();
    let surface = Terminal::new(TestBackend::new(width, height)).unwrap_or_else(never);
    (
        Screen::new(Box::new(Virtual {
            terminal: surface,
            frames: terminal.frames,
            size: terminal.size,
        })),
        Input::new(terminal.events, None),
    )
}
