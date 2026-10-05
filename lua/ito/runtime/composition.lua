local class = require("ito.class")
local is_view = require("ito.runtime.element").is_view
local Node = require("ito.runtime.node")
local scope = require("ito.runtime.scope")

local function kind(element)
    return element.view or getmetatable(element)
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
        node = Node(kind(element))
        slots[slot] = node
    end
    node.seen = self.generation
    local composed = element:compose(self, node, environment)
    if composed == element and (element.overlays or element.readers) then
        element:attach(self, node, environment)
    end
    if not node.lazy then
        node:sweep(self.generation)
    end
    return composed
end

return Composition
