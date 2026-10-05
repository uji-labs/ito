local Call = require("ito.runtime.call").Call
local class = require("ito.class")
local is_view = require("ito.runtime.element").is_view
local Node = require("ito.runtime.node")
local scope = require("ito.runtime.scope")

local function kind(element)
    local meta = getmetatable(element)
    if meta == Call then
        return element.view
    end
    return meta
end

local Composition = class()

function Composition:init(invalidate)
    self.root = Node()
    self.generation = 0
    self.notify = invalidate
    self.dirty = true
end

function Composition:invalidate()
    self.dirty = true
    if self.notify then
        self.notify()
    end
end

function Composition:compose(element)
    self.generation = self.generation + 1
    self.dirty = false
    local composed = self:place(element, self.root, 1, scope.EMPTY)
    self.root:sweep(self.generation)
    return composed
end

function Composition:place(element, parent, index, environment)
    if not element then
        return nil
    end
    if not is_view(element) then
        error("a view must give a view, not a " .. type(element), 0)
    end
    local slots, slot = parent.children, index
    if element.key ~= nil then
        slots, slot = parent.keyed, parent:slot(element.key)
    end
    local node = slots[slot]
    if not node or node.kind ~= kind(element) then
        node = Node(kind(element), parent)
        slots[slot] = node
    end
    node.seen = self.generation
    local again = node.placed == element
    if again and node.placed_environment == environment and not node.stale and not node.invalid then
        return node.placed_result
    end
    local composed = element:compose(self, node, environment)
    if composed == element and (element.overlays or element.readers) then
        element:attach(self, node, environment)
    end
    if not node.lazy and node.kept ~= self.generation then
        node:sweep(self.generation)
    end
    if again and composed == element then
        element.rect, element.settled = nil, nil
        element.revision = (element.revision or 0) + 1
    end
    node.placed, node.placed_environment, node.placed_result = element, environment, composed
    node.stale = false
    return composed
end

return Composition
