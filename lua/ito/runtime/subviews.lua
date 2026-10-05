local call = require("ito.runtime.call")
local class = require("ito.class")
local Primitive = require("ito.runtime.primitive")

local M = {}

local Subview = class()

function Subview:init(target)
    self.target = target
    self.weight = target.weight
    self.width = target.fixed_width
    self.height = target.fixed_height
    self.alignment = target.aligned
    self.layout_id = target.tag
end

function Subview:compose(composition)
    if self.used == composition.generation then
        error("a subview can be placed once", 0)
    end
    self.used = composition.generation
    return self.target
end

local Subviews = class()
call.deferring(Subviews)

function M.Subviews(children, builder)
    if type(children) ~= "table" then
        error("ito.Subviews takes a list of views first", 2)
    end
    if type(builder) ~= "function" then
        error("ito.Subviews takes a function that builds from the subviews second", 2)
    end
    return setmetatable({ children = children, builder = builder, pending = {} }, Subviews)
end

function Subviews:compose(composition, node, environment)
    local group = composition:place(Primitive(self.children), node, "content", environment)
    local subviews = {}
    for index, child in ipairs(group.composed) do
        subviews[index] = Subview(child)
    end
    local built = call.Build({ build = self.builder, value = subviews })
    if #self.pending > 0 then
        call.forward(built, self.pending)
    end
    return composition:place(built, node, "built", environment)
end

return M
