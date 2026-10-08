local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local function shrunk(children, extents, room)
    local over = -room
    for _, extent in ipairs(extents) do
        if type(extent) == "number" then
            over = over + extent
        end
    end
    for index, child in ipairs(children) do
        if over <= 0 then
            return
        end
        if child and child.shrinks and type(extents[index]) == "number" then
            local cut = math.min(extents[index], over)
            extents[index], over = extents[index] - cut, over - cut
        end
    end
end

local function spaced(children, extents, gap)
    if not gap or gap == 0 then
        return children, extents
    end
    local members, sized, shown = {}, {}, false
    for index, child in ipairs(children) do
        if not child.is_hidden then
            if shown then
                members[#members + 1], sized[#sized + 1] = false, gap
            end
            shown = true
        end
        members[#members + 1], sized[#sized + 1] = child, extents[index]
    end
    return members, sized
end

local function gaps(view)
    local shown = 0
    for _, child in ipairs(view.composed or {}) do
        if not child.is_hidden then
            shown = shown + 1
        end
    end
    return (view.gap or 0) * math.max(shown - 1, 0)
end

local function stacked(view, frame, down)
    local inner = view.inner
    local extents = {}
    for index, child in ipairs(view.composed) do
        extents[index] = child:extent(frame, inner, down)
    end
    local members, sized = spaced(view.composed, extents, view.gap)
    shrunk(members, sized, down and inner.height or inner.width)
    local rects = layout.stack(inner, sized, down)
    for index, child in ipairs(members) do
        if child then
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
end

local function spacing(self, cells)
    if type(cells) ~= "number" or cells < 0 or cells % 1 ~= 0 then
        error("spacing must be a whole number of cells, not " .. tostring(cells), 2)
    end
    self.gap = cells
    return self
end

local VStack = class(View)

VStack.spacing = spacing

function VStack:content_height(frame, width)
    local total = gaps(self)
    for _, child in ipairs(self.composed or {}) do
        if child.fixed_height then
            total = total + child.fixed_height
        elseif not child.weight and not child.fraction then
            total = total + child:measure(frame, width)
        end
    end
    return total
end

function VStack:arrange(frame)
    stacked(self, frame, true)
end

local HStack = class(View)

HStack.spacing = spacing

function HStack:content_height(frame, width)
    local row = layout.rect(0, 0, width, 0)
    local extents = {}
    for index, child in ipairs(self.composed or {}) do
        extents[index] = child:extent(frame, row, false)
    end
    local members, sized = spaced(self.composed or {}, extents, self.gap)
    local rects = layout.stack(row, sized, false)
    local most = 0
    for index, child in ipairs(members) do
        if child then
            most = math.max(most, child:measure(frame, rects[index].width))
        end
    end
    return most
end

function HStack:content_width(frame)
    local total = gaps(self)
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
