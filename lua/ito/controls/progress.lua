local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local function number(value, name)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, name .. " must be a finite number")
    return value
end

local Progress = class(View)

function Progress:init(value)
    View.init(self, {})
    self.value = math.max(0, math.min(1, number(value, "Progress")))
end

function Progress:content_height()
    return self.caption and 2 or 1
end

function Progress:draw_content(frame)
    local inner, styles = self.inner, frame.ctx.styles
    local row = inner.y
    if self.caption then
        frame:lines(inner, { { { self.caption, styles.dim } } })
        row = row + 1
    end
    local width = math.max(0, inner.width)
    local filled = math.floor(width * self.value)
    frame:lines(layout.rect(inner.x, row, width, 1), {
        { { string.rep("━", filled), styles.accent }, { string.rep("─", width - filled), styles.dim } },
    })
end

return Progress
