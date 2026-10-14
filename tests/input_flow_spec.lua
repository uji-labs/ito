local ito = require("ito")
local screen = require("support.screen")

local function key(s, name)
    local handled = s.window:event({ type = "key", key = name, ctrl = false, alt = false, meta = false, shift = false })
    return table.concat(s:rows(), "\n"), handled
end
local function paste(s, value)
    s.window:event({ type = "paste", text = value })
    return table.concat(s:rows(), "\n")
end
local function has(rows, value)
    assert.is_not_nil(rows:find(value, 1, true), "Expected " .. value .. " in:\n" .. rows)
end

describe("shared input flow", function()
    it("runs the browser flow with terminal keys, editing, cancellation, and review", function()
        local s = screen.new(48, 24)
        s:show(assert(loadfile("web/examples/flow.lua"))())
        has(key(s, "down"), "Read a chapter")
        has(key(s, "enter"), "EDIT NAME")
        paste(s, " changed")
        has(key(s, "esc"), "CHOOSE AN ITEM")
        has(key(s, "enter"), "Read a chapter")
        local rows = paste(s, " together")
        has(rows, "Read a chapter together")
        has(key(s, "enter"), "REVIEW")
        has(key(s, "esc"), "EDIT NAME")
        key(s, "enter")
        has(key(s, "enter"), "SAVED")
        has(table.concat(s:rows(), "\n"), "Read a chapter together")
        has(key(s, "enter"), "CHOOSE AN ITEM")
    end)

    it("routes Tab, pointer focus, and paste to one field and draws one caret", function()
        local a, b = ito.state(""), ito.state("")
        local s = screen.new(30, 6)
        s:show(function()
            return ito.VStack({ ito.TextField(a):label("A"), ito.TextField(b):label("B") }):spacing(1)
        end)
        paste(s, "alpha")
        assert.equal("alpha", a.value)
        local _, handled = key(s, "tab")
        assert.is_true(handled)
        local rows = paste(s, "日本語")
        assert.equal("日本語", b.value)
        local _, cursors = rows:gsub("█", "")
        assert.equal(1, cursors)
        local _, escaped = key(s, "tab")
        assert.is_false(escaped)
        s.window:press(1, 1)
        s.window:release({})
        s:rows()
        paste(s, "!")
        assert.equal("alpha!", a.value)
        s.window:event({ type = "focus", focused = false })
        rows = table.concat(s:rows(), "\n")
        assert.is_nil(rows:find("█", 1, true))
        key(s, "x")
        assert.equal("alpha!", a.value)
    end)

    it("honors a new Lua focus request and ignores hidden and disabled controls", function()
        local first, second, move = ito.state(""), ito.state(""), ito.state(false)
        local s = screen.new(30, 8)
        s:show(function()
            return ito.VStack({
                ito.TextField(first):focused(not move.value),
                ito.Button("Disabled", function()
                    error("disabled")
                end):disabled(),
                ito.TextField(ito.state("")):hidden():invisible(),
                ito.TextField(second):focused(move.value),
            })
        end)
        paste(s, "a")
        move.value = true
        s:rows()
        paste(s, "b")
        assert.equal("a", first.value)
        assert.equal("b", second.value)
        assert.equal(2, #s.window.focusables)
    end)

    it("keeps a border style on the border instead of tinting its contents", function()
        local s = screen.new(12, 3)
        s:show(function(ctx)
            return ito.Text("readable"):padding({ leading = 1 }):border(ctx.borders.plain, { color = ito.Color.red })
        end)
        for _, span in ipairs(s.screen:spans(1)) do
            if span.text:find("readable", 1, true) then
                assert.is_nil(span.fg)
                return
            end
        end
        error("Expected readable content")
    end)

    it("keeps long text editable and only reports actual changes", function()
        local value, changes = ito.state(""), 0
        local s = screen.new(8, 2)
        s:show(function()
            return ito.TextField(value):on_change(function()
                changes = changes + 1
            end)
        end)
        has(paste(s, "abcdefghijkl"), "fghijkl")
        key(s, "left")
        key(s, "left")
        assert.equal(1, changes)
        key(s, "backspace")
        assert.equal("abcdefghikl", value.value)
        assert.equal(2, changes)
    end)

    it("keeps a pasted paragraph on the one line an editor holds", function()
        local value = ito.state("")
        local s = screen.new(30, 2)
        s:show(function()
            return ito.TextField(value)
        end)
        has(paste(s, "first\r\nsecond\n\nthird"), "first second third")
        assert.equal("first second third", value.value)
    end)

    it("writes a pasted answer into the written row of a choices control", function()
        local value, wrote = ito.state(""), nil
        local s = screen.new(30, 4)
        s:show(function()
            return ito.Choices({ { label = "Morning walk" } })
                :on_choose(function()
                    value.value = "chosen"
                end)
                :on_other(function(text)
                    wrote = text
                end)
        end)
        key(s, "down")
        paste(s, "Read a\nchapter")
        key(s, "enter")
        assert.equal("Read a chapter", wrote)
        assert.equal("", value.value)
    end)
end)
