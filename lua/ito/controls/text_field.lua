local class = require("ito.class")
local Line = require("ito.line")
local typing = require("ito.typing")
local View = require("ito.view")

local TextField = class(View)

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

function TextField:hidden()
    self.masked = true
    return self
end

function TextField:on_submit(handler)
    self.submit = handler
    return self
end

function TextField:focused()
    self.wanted = true
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
    return 1
end

function TextField:draw_content(frame)
    local ctx, line = frame.ctx, self:field()
    local spans = ctx:typed(
        { text = line.text, cursor = line.cursor, hidden = self.masked },
        { text = ctx.styles.input, cursor = ctx.styles.cursor }
    )
    if line.text == "" and self.hint then
        spans[#spans + 1] = { self.hint, ctx.styles.dim }
    end
    frame:lines(self.inner, { spans })
    frame:focusable(self.memo, function(chord)
        return self:handle(chord)
    end, self.wanted)
end

function TextField:handle(chord)
    local line = self:field()
    if typing.typed(chord) then
        line:insert(chord.key)
    elseif chord.key == "enter" and self.submit then
        self.submit(line.text)
        return true
    elseif not typing.edit(line, chord.key) then
        return false
    end
    self.value.value = line.text
    return true
end

return TextField
