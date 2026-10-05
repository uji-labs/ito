local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local Highlight = class(View)

function Highlight:init()
    View.init(self, {})
    self.weight = 1
end

function Highlight:paint(frame)
    local window = frame.window
    if not window then
        return
    end
    local style = frame.ctx.styles.selection
    for _, rect in ipairs(window.selection:rects(window:panes(frame), self.rect.width)) do
        frame:fill(layout.rect(rect.x, rect.y, rect.width, rect.height), style)
    end
end

return Highlight
