local class = require("ito.class")

local M = {}

local unpack = table.unpack or unpack

local current
local EMPTY = {}

local Node = class()

function Node:init(kind)
    self.kind = kind
    self.children = {}
    self.keyed = {}
    self.states = {}
    self.memo = {}
    self.hook = 0
    self.seen = 0
end

function Node:sweep(generation)
    for index, child in pairs(self.children) do
        if child.seen ~= generation then
            self.children[index] = nil
        end
    end
    for key, child in pairs(self.keyed) do
        if child.seen ~= generation then
            self.keyed[key] = nil
        end
    end
end

local State = {}

local WEAK = { __mode = "k" }

State.__index = function(self, key)
    if key == "value" then
        if current then
            rawget(self, "readers")[current.composition] = true
        end
        return rawget(self, "current")
    end
end

State.__newindex = function(self, key, value)
    if key ~= "value" then
        error("a state only has a value", 2)
    end
    if rawget(self, "current") ~= value then
        rawset(self, "current", value)
        for composition in pairs(rawget(self, "readers")) do
            composition:invalidate()
        end
    end
end

local function fresh(initial, owner)
    local readers = setmetatable({}, WEAK)
    if owner then
        readers[owner] = true
    end
    return setmetatable({ current = initial, readers = readers }, State)
end

function M.state(initial)
    local node = current
    if not node then
        return fresh(initial)
    end
    node.hook = node.hook + 1
    local state = node.states[node.hook]
    if not state then
        state = fresh(initial, node.composition)
        node.states[node.hook] = state
    end
    return state
end

function M.remember(factory)
    local node = current
    if not node then
        error("ito.remember works only inside a view while it is composed", 2)
    end
    node.hook = node.hook + 1
    local slot = node.states[node.hook]
    if not slot then
        slot = { kept = factory() }
        node.states[node.hook] = slot
    end
    return slot.kept
end

function M.is_view(value)
    return type(value) == "table" and type(value.compose) == "function"
end

local Local = {}

Local.__index = function(self, key)
    if key == "current" then
        local environment = current and current.environment or EMPTY
        local value = environment[self]
        if value == nil then
            return rawget(self, "default")
        end
        return value
    end
    return Local[key]
end

function M.Local(default)
    return setmetatable({ default = default }, Local)
end

function Local:set(value)
    rawset(self, "default", value)
end

M.Theme = M.Local(nil)

local Provide = class()

function Provide:init(owner, value, child)
    self.owner = owner
    self.value = value
    self.child = child
end

function Provide:compose(composition, node, environment)
    local inner = setmetatable({ [self.owner] = self.value }, { __index = environment })
    return composition:place(self.child, node, 1, inner)
end

function Local:provide(value, child)
    return Provide(self, value, child)
end

local Call = class()

Call.__index = function(_, key)
    local own = Call[key]
    if own ~= nil then
        return own
    end
    local modifier = M.modifiers and M.modifiers[key]
    if type(modifier) ~= "function" then
        return nil
    end
    return function(self, ...)
        local pending = rawget(self, "pending")
        pending[#pending + 1] = { modifier, select("#", ...), ... }
        return self
    end
end

function Call:init(view, props)
    self.view = view
    self.props = props or {}
    self.key = self.props.key
    self.pending = {}
end

function Call:compose(composition, node, environment)
    local outer = current
    current = node
    node.hook = 0
    node.composition = composition
    node.environment = environment
    local ok, result = pcall(self.view.body, self.props)
    current = outer
    if not ok then
        error(result, 0)
    end
    local placed = composition:place(result, node, 1, environment)
    if placed then
        for _, change in ipairs(self.pending) do
            change[1](placed, unpack(change, 3, change[2] + 2))
        end
    end
    return placed
end

local View = {}
View.__index = View

View.__call = function(self, props)
    return Call(self, props)
end

function M.view(body)
    if type(body) ~= "function" then
        error("ito.view needs a function that returns a view", 2)
    end
    return setmetatable({ body = body }, View)
end

function M.body(content)
    if getmetatable(content) == View then
        return content
    end
    return M.view(function()
        return content()
    end)
end

local Primitive = class()

M.Primitive = Primitive

function Primitive:init(props)
    props = props or {}
    self.props = props
    self.key = props.key
    self.children = {}
    for index, child in ipairs(props) do
        self.children[index] = child
    end
end

function Primitive:compose(composition, node, environment)
    self.memo = node.memo
    local composed = {}
    for index, element in ipairs(self.children) do
        local child = composition:place(element, node, index, environment)
        if child then
            composed[#composed + 1] = child
        end
    end
    self.composed = composed
    return self
end

local function kind(element)
    return element.view or getmetatable(element)
end

local Composition = class()

M.Composition = Composition

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
    local composed = self:place(element, self.root, 1, EMPTY)
    self.root:sweep(self.generation)
    return composed
end

function Composition:place(element, parent, index, environment)
    if not element then
        return nil
    end
    if not M.is_view(element) then
        error("a view must give a view, not a " .. type(element), 0)
    end
    local slots, slot = parent.children, index
    if element.key ~= nil then
        slots, slot = parent.keyed, element.key
    end
    local node = slots[slot]
    if not node or node.kind ~= kind(element) then
        node = Node(kind(element))
        slots[slot] = node
    end
    node.seen = self.generation
    local composed = element:compose(self, node, environment)
    if not node.lazy then
        node:sweep(self.generation)
    end
    return composed
end

return M
