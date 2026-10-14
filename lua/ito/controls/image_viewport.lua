local class = require("ito.class")
local layout = require("ito.layout")
local validate = require("ito.validate")

local Viewport = class()

function Viewport:init()
    self:reset()
end

function Viewport:reset()
    self.zoom, self.x, self.y = 1, 0, 0
end

function Viewport:zoom_to(scale)
    self.zoom = layout.clamp(validate.finite(scale, "zoom"), 0.1, 64)
end

function Viewport:zoom_by(factor)
    self:zoom_to(self.zoom * validate.finite(factor, "zoom factor"))
end

function Viewport:pan_to(x, y)
    self.x, self.y = layout.clamp(validate.finite(x, "pan x"), -1, 1), layout.clamp(validate.finite(y, "pan y"), -1, 1)
end

function Viewport:pan_by(x, y)
    self:pan_to(self.x + validate.finite(x, "pan x"), self.y + validate.finite(y, "pan y"))
end

function Viewport.is(value)
    return getmetatable(value) == Viewport
end

return Viewport
