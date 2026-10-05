local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local Child = class()

function Child:init(view, frame)
    self.view, self.frame = view, frame
    self.weight = view.weight
    self.layout_id = view.tag
    self.alignment = view.aligned
end

function Child:measure(room)
    local view = self.view
    local width = view.fixed_width or (not view.weight and view:natural_width(self.frame)) or room.width
    if width and room.width then
        width = math.min(width, room.width)
    end
    return width, width and view:measure(self.frame, width)
end

function Child:place(x, y, width, height)
    self.rect = layout.rect(x, y, width, height)
end

local function measured(container, frame, room)
    local children = {}
    for index, view in ipairs(container.composed or {}) do
        children[index] = Child(view, frame)
    end
    local width, height, place = container.measure_children(children, room)
    return width, height, place, children
end

local function Layout(measure)
    if type(measure) ~= "function" then
        error("ito.Layout needs a function that measures and places its children", 2)
    end
    local Container = class(View)
    Container.measure_children = measure

    function Container:content_height(frame, width)
        local _, height = measured(self, frame, { width = width })
        return height or 0
    end

    function Container:content_width(frame)
        return (measured(self, frame, {}))
    end

    function Container:arrange(frame, inner)
        local _, _, place, children = measured(self, frame, { width = inner.width, height = inner.height })
        if place then
            place(inner.x, inner.y)
        end
        self.placed = {}
        for _, child in ipairs(children) do
            if child.rect then
                child.view:place(frame, child.rect)
                self.placed[#self.placed + 1] = child.view
            end
        end
    end

    function Container:paint(frame)
        if self.fill then
            frame:fill(self.rect, self.fill)
        end
        if self:framed() then
            frame:chrome(self)
        end
        for _, view in ipairs(self.placed or {}) do
            view:draw(frame)
        end
        self:draw_extras(frame)
        if self.click then
            frame:clickable(self.rect, self.click)
        end
    end

    return Container
end

return Layout
