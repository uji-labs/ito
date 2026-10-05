local scope = require("ito.runtime.scope")

local M = {}

local State = {}

local WEAK = { __mode = "k" }

State.__index = function(self, key)
    if key == "value" then
        if scope.current then
            rawget(self, "readers")[scope.current.composition] = true
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
    local node = scope.current
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
    local node = scope.current
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

return M
