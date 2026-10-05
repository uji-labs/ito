local class = require("ito.class")
local text = require("ito.text")
local View = require("ito.view")

local Lines = class(View)

function Lines:init(rows)
    View.init(self, {})
    if type(rows) ~= "table" then
        error("Lines takes a list of lines, not a " .. type(rows), 3)
    end
    self.rows = rows
end

function Lines:content_height()
    return #self.rows
end

function Lines:content_width()
    return text.widest(self.rows)
end

function Lines:draw_content(frame)
    frame:lines(self.inner, self.rows)
end

return Lines
