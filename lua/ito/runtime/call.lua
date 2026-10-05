local class = require("ito.class")
local identity = require("ito.runtime.identity").identity
local is_view = require("ito.runtime.element").is_view
local Provide = require("ito.runtime.environment").Provide
local scope = require("ito.runtime.scope")

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

function Call:compose(composition, node, environment)
    local outer = scope.current
    scope.current = node
    node.hook = 0
    node.composition = composition
    node.environment = environment
    local ok, result = pcall(self.view.body, self.props)
    scope.current = outer
    if not ok then
        error(result, 0)
    end
    if #self.pending > 0 then
        forward(result, self.pending)
    end
    return composition:place(result, node, 1, environment)
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

M.deferring = deferring
M.forward = forward
M.Call = Call

return M
