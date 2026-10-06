local class = require("ito.class")
local text = require("ito.text")
local View = require("ito.view")

local Lines = class(View)

function Lines:init(rows, value)
    View.init(self, {})
    if type(rows) ~= "table" and type(rows) ~= "function" then
        error("Lines takes a list of lines, or a function that gives them for a width, not a " .. type(rows), 3)
    end
    self.source, self.value = rows, value
end

function Lines:rows(width)
    local source = self.source
    if type(source) == "table" then
        return source
    end
    local kept, value = self.memo or self, self.value
    if kept.lines_source ~= source or kept.lines_value ~= value or kept.lines_width ~= width then
        kept.lines_source, kept.lines_value, kept.lines_width = source, value, width
        kept.lines = source(width, value)
    end
    return kept.lines
end

function Lines:content_height(_, width)
    return #self:rows(width)
end

function Lines:content_width()
    if type(self.source) == "function" then
        return nil
    end
    return text.widest(self.source)
end

function Lines:draw_content(frame)
    frame:lines(self.inner, self:rows(self.inner.width))
end

return Lines
