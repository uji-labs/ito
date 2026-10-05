local scope = require("ito.runtime.scope")

local M = {}

local State = {}

local WEAK = { __mode = "k" }

function M.readers()
    return setmetatable({}, WEAK)
end

function M.notify(readers)
    local asked = {}
    for node in pairs(readers) do
        node:touch()
        asked[node.composition] = true
    end
    for composition in pairs(asked) do
        composition:invalidate()
    end
end

State.__index = function(self, key)
    if key == "value" then
        if scope.current then
            rawget(self, "readers")[scope.current] = true
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
        M.notify(rawget(self, "readers"))
    end
end

local function fresh(initial, owner)
    local readers = M.readers()
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
        state = fresh(initial, node)
        node.states[node.hook] = state
    end
    return state
end

local function unchanged(slot, count, ...)
    if slot.count ~= count then
        return false
    end
    for index = 1, count do
        if slot.keys[index] ~= select(index, ...) then
            return false
        end
    end
    return true
end

function M.remember(factory, ...)
    local node = scope.current
    if not node then
        error("ito.remember works only inside a view while it is composed", 2)
    end
    node.hook = node.hook + 1
    local count = select("#", ...)
    local slot = node.states[node.hook]
    if not slot or not unchanged(slot, count, ...) then
        slot = { kept = factory(), count = count, keys = { ... } }
        node.states[node.hook] = slot
    end
    return slot.kept
end

return M
