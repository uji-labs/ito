local class = require("ito.class")
local Image = require("ito.views.image")
local ImageViewport = require("ito.controls.image_viewport")
local ImageWheel = require("ito.image").ImageWheel

local Viewer = class(Image)

function Viewer:state(viewport)
    if not ImageViewport.is(viewport) then
        error("state takes an ito.ImageViewport", 2)
    end
    self.viewport = viewport
    return self
end

function Viewer:focused()
    self.wanted = true
    return self
end

function Viewer:wheel(policy)
    self.wheel_policy = Image.choice(policy, ImageWheel, "wheel")
    return self
end

function Viewer:on_change(handler)
    if type(handler) ~= "function" then
        error("on_change takes a function receiving the viewport", 2)
    end
    self.changed = handler
    return self
end

function Viewer:position()
    if self.viewport then
        return self.viewport
    end
    self.memo.viewport = self.memo.viewport or ImageViewport()
    return self.memo.viewport
end

function Viewer:options()
    local options, viewport = Image.options(self), self:position()
    options.zoom = math.floor(Image.number(viewport.zoom, 0.1, 64, "zoom") * 1000 + 0.5)
    options.pan_x = math.floor(Image.number(viewport.x, -1, 1, "pan x") * 1000 + 0.5)
    options.pan_y = math.floor(Image.number(viewport.y, -1, 1, "pan y") * 1000 + 0.5)
    return options
end

function Viewer:notify()
    if self.changed then
        self.changed(self:position())
    end
end

function Viewer:handle(chord)
    if chord.ctrl or chord.alt or chord.meta then
        return false
    end
    local key, viewport = chord.key, self:position()
    if key == "+" or key == "=" then
        viewport:zoom_by(1.25)
    elseif key == "-" then
        viewport:zoom_by(0.8)
    elseif key == "0" or key == "home" then
        viewport:reset()
    elseif key == "left" then
        viewport:pan_by(-0.1, 0)
    elseif key == "right" then
        viewport:pan_by(0.1, 0)
    elseif key == "up" then
        viewport:pan_by(0, -0.1)
    elseif key == "down" then
        viewport:pan_by(0, 0.1)
    else
        return false
    end
    self:notify()
    return true
end

function Viewer:scroll(rows)
    local viewport = self:position()
    if self.wheel_policy == ImageWheel.zoom then
        viewport:zoom_by(1.1 ^ -math.max(-30, math.min(30, rows)))
    elseif self.wheel_policy == ImageWheel.pan then
        viewport:pan_by(0, rows * 0.05)
    end
    self:notify()
end

function Viewer:draw_content(frame)
    Image.draw_content(self, frame)
    local clip = frame.clipping and frame.overlap(frame.clipping, self.inner) or self.inner
    if not frame:shows(clip) then
        return
    end
    frame:focusable(self:position(), function(chord)
        return self:handle(chord)
    end, self.wanted)
    if self.wheel_policy and self.wheel_policy ~= ImageWheel.pass then
        frame:scrollable(clip, self, nil, 1)
    end
end

return Viewer
