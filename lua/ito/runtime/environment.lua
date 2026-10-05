local class = require("ito.class")
local scope = require("ito.runtime.scope")

local M = {}

local Local = {}

Local.__index = function(self, key)
    if key == "current" then
        local environment = scope.current and scope.current.environment or scope.EMPTY
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

M.Provide = Provide

return M
