local class = require("ito.class")
local text = require("ito.text")
local View = require("ito.view")

local Checkbox = class(View)

function Checkbox:init(content, value)
    View.init(self, {})
    assert(type(content) == "string", "Checkbox takes a text label")
    assert(type(value) == "table" and type(value.value) == "boolean", "Checkbox takes a boolean state")
    self.content, self.value = content, value
    self.click = function()
        self:set(not self.value.value)
    end
end

function Checkbox:description(detail)
    assert(type(detail) == "string", "description takes a string")
    self.detail = detail
    return self
end

function Checkbox:set(value)
    if self.is_disabled then
        return
    end
    self.value.value = value == true
    if self.changed then
        self.changed(self.value.value)
    end
end

function Checkbox:rows(width, active, styles)
    local rows = {}
    local wrap_width = math.max(1, width - 6)
    for index, part in ipairs(text.wrap(self.content, wrap_width)) do
        local prefix = index == 1 and ((active and "› " or "  ") .. (self.value.value and "[x] " or "[ ] ")) or "      "
        rows[#rows + 1] = { { prefix .. part, self.is_disabled and styles.dim or styles.text } }
    end
    if self.detail then
        for _, part in ipairs(text.wrap(self.detail, wrap_width)) do
            rows[#rows + 1] = { { "      " .. part, styles.dim } }
        end
    end
    return rows
end

function Checkbox:content_height(frame, width)
    return #self:rows(width, false, frame.ctx.styles)
end

function Checkbox:draw_content(frame)
    local active = frame.window and frame.window:is_focused(self.memo)
    local rows = self:rows(self.inner.width, active, frame.ctx.styles)
    frame:lines(self.inner, rows)
    if not self.is_disabled then
        frame:focusable(self.memo, function(chord)
            if chord.key == "enter" or chord.key == " " then
                self:set(not self.value.value)
                return true
            end
            return false
        end, self.wanted, self)
    end
end

return Checkbox
