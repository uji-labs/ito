local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local function stacked(view, frame, down)
    local inner = view.inner
    local extents = {}
    for index, child in ipairs(view.composed) do
        extents[index] = child:extent(frame, inner, down)
    end
    local rects = layout.stack(inner, extents, down)
    for index, child in ipairs(view.composed) do
        local rect = rects[index]
        local at = child.aligned
        if at and down then
            local width = math.min(child.fixed_width or child:natural_width(frame) or rect.width, rect.width)
            rect = layout.rect(rect.x + math.floor((rect.width - width) * at.x), rect.y, width, rect.height)
        elseif at then
            local height = math.min(child.fixed_height or child:measure(frame, rect.width), rect.height)
            rect = layout.rect(rect.x, rect.y + math.floor((rect.height - height) * at.y), rect.width, height)
        end
        child:place(frame, rect)
    end
end

local VStack = class(View)

function VStack:content_height(frame, width)
    local total = 0
    for _, child in ipairs(self.composed or {}) do
        if not child.weight and not child.fraction then
            total = total + (child.fixed_height or child:measure(frame, width))
        end
    end
    return total
end

function VStack:arrange(frame)
    stacked(self, frame, true)
end

local HStack = class(View)

function HStack:content_height(frame, width)
    local most = 0
    for _, child in ipairs(self.composed or {}) do
        most = math.max(most, child:measure(frame, width))
    end
    return most
end

function HStack:content_width(frame)
    local total = 0
    for _, child in ipairs(self.composed or {}) do
        local used = child.fixed_width or child:natural_width(frame)
        if not used then
            return nil
        end
        total = total + used
    end
    return total
end

function HStack:arrange(frame)
    stacked(self, frame, false)
end

return { VStack = VStack, HStack = HStack }
