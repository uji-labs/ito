local class = require("ito.class")
local described = require("ito.runtime.identity").described
local is_view = require("ito.runtime.element").is_view

local Primitive = class()

function Primitive:init(props)
    props = props or {}
    self.props = props
    self.children = {}
    for index, child in ipairs(props) do
        self.children[index] = child
    end
end

function Primitive:compose(composition, node, environment)
    self.memo = node.memo
    local composed, taken = {}, {}
    for index, element in ipairs(self.children) do
        local key = is_view(element) and element.key or nil
        if key ~= nil then
            local slot = node:slot(key)
            if taken[slot] then
                error("two views in one container have the id " .. described(key), 0)
            end
            taken[slot] = true
        end
        local child = composition:place(element, node, index, environment)
        if child then
            composed[#composed + 1] = child
        end
    end
    self.composed = composed
    return self
end

return Primitive
