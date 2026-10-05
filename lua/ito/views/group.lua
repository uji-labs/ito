local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local Group = class(View)

function Group:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    self.generation = composition.generation
    self.made = {}
    return self
end

function Group:count()
    return #self.children
end

function Group:child(index)
    local made = self.made[index]
    if made == nil then
        made = self.composition:place(self.children[index], self.node, index, self.environment) or false
        self.made[index] = made
    end
    return made or nil
end

function Group:finish()
    if self.generation == self.composition.generation then
        self.node:sweep(self.generation)
    end
end

function Group:content_height(frame, width)
    local total = 0
    for index = 1, self:count() do
        local child = self:child(index)
        total = total + (child and child:measure(frame, width) or 0)
    end
    return total
end

function Group:arrange(frame, inner)
    local y = inner.y
    self.composed = {}
    for index = 1, self:count() do
        local child = self:child(index)
        if child then
            local height = child:measure(frame, inner.width)
            child:place(frame, layout.rect(inner.x, y, inner.width, height))
            self.composed[#self.composed + 1] = child
            y = y + height
        end
    end
    self:finish()
end

function Group.is(value)
    return getmetatable(value) == Group
end

return Group
