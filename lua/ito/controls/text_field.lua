local class = require("ito.class")
local Line = require("ito.line")
local text = require("ito.text")
local View = require("ito.view")

local SINGLE = "^" .. text.CHAR .. "$"

local function typed(chord)
    return not chord.ctrl and not chord.alt and type(chord.key) == "string" and chord.key:match(SINGLE) ~= nil
end

local EDITS = {
    left = "left",
    right = "right",
    home = "home",
    ["end"] = "tail",
    backspace = "backspace",
    delete = "delete_forward",
}

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
    if typed(chord) then
        line:insert(chord.key)
    elseif chord.key == "enter" and self.submit then
        self.submit(line.text)
        return true
    elseif EDITS[chord.key] then
        line[EDITS[chord.key]](line)
    else
        return false
    end
    self.value.value = line.text
    return true
end

return TextField
