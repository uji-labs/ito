local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local Dock = class(View)

function Dock:arrange(frame, inner)
    local items = self.composed
    local entries, natural = {}, {}
    for index, item in ipairs(items) do
        local split = item.side or View.Side.top
        local down = View.vertical(split)
        local total = down and inner.height or inner.width
        local fixed = down and item.fixed_height or item.fixed_width
        local extent = fixed
        if not extent and item.fraction then
            extent = math.floor(total * item.fraction)
        elseif not extent and item.weight then
            extent = "fill"
        elseif not extent then
            extent = 0
            natural[index] = true
        end
        entries[index] = { split = split, float = item.floating, extent = extent }
    end
    local rects = layout.dock(inner, entries)
    for index, item in ipairs(items) do
        if natural[index] then
            entries[index].extent = item:measure(frame, rects[index].width)
        end
    end
    rects = layout.dock(inner, entries)
    for index, item in ipairs(items) do
        item:place(frame, rects[index])
    end
    self.items = items
end

function Dock:draw(frame)
    if self:framed() then
        frame:chrome(self)
    end
    self:draw_extras(frame)
    for _, floating in ipairs({ false, true }) do
        for _, item in ipairs(self.items or {}) do
            if (item.floating ~= nil) == floating then
                item:draw(frame)
            end
        end
    end
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

return Dock
