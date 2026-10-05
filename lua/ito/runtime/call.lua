local class = require("ito.class")
local environment = require("ito.runtime.environment")
local host = require("ito.host")
local identity = require("ito.runtime.identity").identity
local is_view = require("ito.runtime.element").is_view
local scope = require("ito.runtime.scope")

local Provide = environment.Provide

local M = {}

local unpack = table.unpack or unpack

local function deferring(owner)
    owner.__index = function(_, key)
        local own = owner[key]
        if own ~= nil then
            return own
        end
        local modifier = scope.modifiers and scope.modifiers[key]
        if type(modifier) ~= "function" then
            return nil
        end
        return function(self, ...)
            local pending = rawget(self, "pending")
            pending[#pending + 1] = { modifier, select("#", ...), ... }
            return self
        end
    end
end

local Call = class()
deferring(Call)

function Call:init(view, props)
    self.view = view
    self.props = props or {}
    self.pending = {}
end

function Call:id(...)
    self.key = identity(...)
    return self
end

local function forward(element, pending)
    if not is_view(element) then
        return
    end
    local queue = rawget(element, "pending")
    if queue then
        for _, change in ipairs(pending) do
            queue[#queue + 1] = change
        end
    elseif getmetatable(element) == Provide then
        forward(element.child, pending)
    else
        for _, change in ipairs(pending) do
            change[1](element, unpack(change, 3, change[2] + 2))
        end
    end
end

local function themed(view, props, node)
    local theme = environment.Theme.current
    local override = theme and theme.views and theme.views[view]
    if not override then
        return view.body(props)
    end
    local ok, result = pcall(override, props)
    if ok then
        node.memo.override_failure = nil
        return result
    end
    local problem = "theme view: " .. tostring(result)
    if node.memo.override_failure ~= problem then
        node.memo.override_failure = problem
        host.report(problem)
    end
    node.hook = 0
    return view.body(props)
end

local function same(kept, props)
    for key, value in pairs(kept) do
        if not rawequal(props[key], value) then
            return false
        end
    end
    for key in pairs(props) do
        if kept[key] == nil then
            return false
        end
    end
    return true
end

local function same_changes(kept, pending)
    if #kept ~= #pending then
        return false
    end
    for index = 1, #pending do
        local before, now = kept[index], pending[index]
        if before[2] ~= now[2] then
            return false
        end
        for at = 1, now[2] + 2 do
            if not rawequal(before[at], now[at]) then
                return false
            end
        end
    end
    return true
end

function Call:compose(composition, node, scoped)
    if
        node.view == self.view
        and not node.invalid
        and node.environment == scoped
        and same(node.props, self.props)
        and same_changes(node.changes, self.pending)
    then
        node.kept = composition.generation
        if node.stale then
            node.stale = false
            node.result = composition:place(node.built, node, 1, scoped)
        end
        return node.result
    end
    local outer = scope.current
    scope.current = node
    node.hook = 0
    node.composition = composition
    node.environment = scoped
    node.view = nil
    local ok, result = pcall(themed, self.view, self.props, node)
    scope.current = outer
    if not ok then
        error(result, 0)
    end
    if #self.pending > 0 then
        forward(result, self.pending)
    end
    local composed = composition:place(result, node, 1, scoped)
    node.view, node.props, node.changes, node.built, node.result = self.view, self.props, self.pending, result, composed
    node.invalid, node.stale = false, false
    return composed
end

local Descriptor = {}
Descriptor.__index = Descriptor

Descriptor.__call = function(self, props)
    return Call(self, props)
end

function M.view(body)
    if type(body) ~= "function" then
        error("ito.view needs a function that returns a view", 2)
    end
    return setmetatable({ body = body }, Descriptor)
end

M.Build = M.view(function(props)
    return props.build(props.value)
end)

function M.body(content)
    if getmetatable(content) == Descriptor then
        return content
    end
    return M.view(function()
        return content()
    end)
end

function M.is_descriptor(value)
    return getmetatable(value) == Descriptor
end

M.deferring = deferring
M.forward = forward
M.Call = Call

return M
