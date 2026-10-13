#![cfg(feature = "canvas")]

use std::cell::RefCell;
use std::rc::Rc;

use ito::tty::{self, canvas, event::Event};
use mlua::{Lua, Table};

fn install(lua: &Lua) -> mlua::Result<()> {
    lua.globals()
        .get::<Table>("package")?
        .get::<Table>("loaded")?
        .set("ito", ito::load(lua)?)
}

#[test]
fn canvas_preserves_styled_wide_cells_links_and_cursor() -> mlua::Result<()> {
    let lua = Lua::new();
    let frames = Rc::new(RefCell::new(Vec::new()));
    let published = Rc::clone(&frames);
    let (terminal, handle) = canvas::terminal(8, 2, move |frame| {
        published.borrow_mut().push(frame);
        Ok(())
    });
    tty::provide(&lua, terminal);
    install(&lua)?;
    lua.load(r"
        local ito = require('ito')
        screen, input = ito.open()
        local style = ito.TextStyle({ foreground = ito.rgb(0x123456), bold = true, underline = true })
        screen:line(0, 0, { { '界x', style, link = 'https://example.com/' } })
        screen:cursor(1, 3, 'bar')
        screen:flush()
    ").exec()?;
    {
        let frames = frames.borrow();
        let first = &frames[0];
        assert_eq!((first.width, first.height), (8, 2));
        assert_eq!(first.cells[0].text, "界");
        assert_eq!(first.cells[0].width, 2);
        assert_eq!(first.cells[1].col, 2);
        assert_eq!(first.cells[1].text, "x");
        assert_eq!(first.cells[0].fg.as_deref(), Some("#123456"));
        assert_eq!(first.cells[0].link.as_deref(), Some("https://example.com/"));
        assert!(first.cells[0].modifiers.contains(&"bold"));
        assert!(first.cells[0].modifiers.contains(&"underline"));
        assert_eq!(
            first
                .cursor
                .as_ref()
                .map(|caret| (caret.row, caret.col, caret.shape)),
            Some((1, 3, "bar"))
        );
    }
    assert!(handle.resize(4, 3));
    assert!(handle.send(Event::Paste {
        text: "hello".into()
    }));
    lua.load(
        r"
        local width, height = screen:size()
        assert(width == 4 and height == 3)
        local resized = input:poll()
        assert(resized.type == 'resize' and resized.width == 4 and resized.height == 3)
        local pasted = input:poll()
        assert(pasted.type == 'paste' and pasted.text == 'hello')
        assert(input:poll() == nil)
        screen:clear()
        screen:cursor()
        screen:flush()
        local ok, err = pcall(function() screen:write('\27[2J') end)
        assert(not ok and tostring(err):find('Canvas does not interpret'))
    ",
    )
    .exec()?;
    let frames = frames.borrow();
    assert_eq!((frames[1].width, frames[1].height), (4, 3));
    assert!(
        frames[1]
            .cells
            .iter()
            .all(|cell| cell.text == " " && cell.link.is_none())
    );
    assert!(frames[1].cursor.is_none());
    Ok(())
}

#[cfg(not(target_family = "wasm"))]
#[test]
fn native_events_keep_their_lua_contract() -> mlua::Result<()> {
    use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
    let lua = Lua::new();
    let (terminal, handle) = tty::virtual_terminal(8, 2);
    tty::provide(&lua, tty::Terminal::Virtual(terminal));
    install(&lua)?;
    assert!(handle.send(Event::Key(KeyEvent::new_with_kind(
        KeyCode::Char('x'),
        KeyModifiers::CONTROL,
        KeyEventKind::Release
    ))));
    assert!(handle.send(Event::Key(KeyEvent::new(
        KeyCode::Char('x'),
        KeyModifiers::CONTROL
    ))));
    assert!(handle.resize(9, 3));
    lua.load(r"
        local _, input = require('ito').open()
        local key = input:poll()
        assert(key.type == 'key' and key.key == 'x' and key.ctrl and not key.alt and not key['repeat'])
        local size = input:poll()
        assert(size.type == 'resize' and size.width == 9 and size.height == 3)
        assert(input:poll() == nil)
    ").exec()
}
