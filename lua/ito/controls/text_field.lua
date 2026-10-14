local class = require("ito.class")
local Line = require("ito.line")
local layout = require("ito.layout")
local typing = require("ito.typing")
local text = require("ito.text")
local View = require("ito.view")

local TextField = class(View)
TextField.text_input = true

function TextField:init(value)
    View.init(self, {})
    if type(value) ~= "table" then
        error("TextField takes an ito.state that holds its text", 3)
    end
    self.value = value
end

function TextField:placeholder(hint)
    self.hint = hint
    return self
end

function TextField:label(caption)
    assert(type(caption) == "string", "label takes a string")
    self.caption = caption
    return self
end

function TextField:on_change(handler)
    assert(type(handler) == "function", "on_change takes a function")
    self.changed = handler
    return self
end

function TextField:hidden()
    self.masked = true
    return self
end

function TextField:on_submit(handler)
    self.submit = handler
    return self
end

function TextField:on_cancel(handler)
    assert(type(handler) == "function", "on_cancel takes a function")
    self.cancel = handler
    return self
end

function TextField:field()
    local memo, wanted = self.memo, self.value.value or ""
    memo.line = memo.line or Line(wanted)
    if memo.line.text ~= wanted then
        memo.line:set(wanted)
    end
    return memo.line
end

function TextField:content_height()
    return self.caption and 2 or 1
end

function TextField:draw_content(frame)
    local ctx, line = frame.ctx, self:field()
    local active = frame.window and frame.window:is_focused(self.memo)
    local spans
    if active then
        spans = ctx:typed(
            { text = line.text, cursor = line.cursor, hidden = self.masked },
            { text = ctx.styles.input, cursor = ctx.styles.cursor }
        )
        -- Keep the insertion point visible as a one-line editor gets longer.
        local chars, width, start = text.chars(spans[1][1]), 0, 1
        for index = #chars, 1, -1 do
            width = width + text.width(chars[index])
            if width >= self.inner.width then
                start = index + 1
                break
            end
        end
        spans[1][1] = table.concat(chars, "", start)
    else
        local shown = self.masked and string.rep(ctx.symbols.mask, text.length(line.text)) or line.text
        spans = { { shown, ctx.styles.input } }
    end
    if line.text == "" and self.hint then
        spans[#spans + 1] = { self.hint, ctx.styles.dim }
    end
    local inner = self.inner
    if self.caption then
        frame:lines(inner, { { { self.caption, ctx.styles.dim } } })
        inner = layout.rect(inner.x, inner.y + 1, inner.width, math.max(0, inner.height - 1))
    end
    frame:lines(inner, { spans })
    frame:focusable(self.memo, function(chord)
        return self:handle(chord)
    end, self.wanted, self)
end

function TextField:handle(chord)
    local line = self:field()
    local previous = line.text
    if chord.type == "paste" then
        line:insert((chord.text:gsub("[\r\n]+", " ")))
    elseif chord.key == "esc" and self.cancel then
        self.cancel(line.text)
        return true
    elseif typing.typed(chord) then
        line:insert(chord.key)
    elseif chord.key == "enter" and self.submit then
        self.submit(line.text)
        return true
    elseif not typing.edit(line, chord.key) then
        return false
    end
    self.value.value = line.text
    if self.changed and previous ~= line.text then
        self.changed(line.text)
    end
    return true
end

return TextField
