local class = require("ito.class")
local layout = require("ito.layout")

local Viewport = class()

local function finite(value, name)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error(name .. " must be a finite number", 3)
    end
    return value
end

function Viewport:init()
    self:reset()
end

function Viewport:reset()
    self.zoom, self.x, self.y = 1, 0, 0
end

function Viewport:zoom_to(scale)
    self.zoom = layout.clamp(finite(scale, "zoom"), 0.1, 64)
end

function Viewport:zoom_by(factor)
    if finite(factor, "zoom factor") <= 0 then
        error("zoom factor must be positive", 2)
    end
    self:zoom_to(self.zoom * factor)
end

function Viewport:pan_to(x, y)
    self.x, self.y = layout.clamp(finite(x, "pan x"), -1, 1), layout.clamp(finite(y, "pan y"), -1, 1)
end

function Viewport:pan_by(x, y)
    self:pan_to(self.x + finite(x, "pan x"), self.y + finite(y, "pan y"))
end

function Viewport.is(value)
    return getmetatable(value) == Viewport
end

return Viewport
