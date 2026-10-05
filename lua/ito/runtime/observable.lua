local scope = require("ito.runtime.scope")
local state = require("ito.runtime.state")

local function inherited(fallback, object, key)
    if type(fallback) == "function" then
        return fallback(object, key)
    end
    return fallback[key]
end

return function(object)
    local base = getmetatable(object)
    if base and base.__observed then
        return object
    end
    local fields, readers = {}, {}
    for key, value in pairs(object) do
        fields[key] = value
    end
    for key in pairs(fields) do
        rawset(object, key, nil)
    end
    local fallback = base and base.__index
    local meta = { __observed = true }
    if base then
        for key, value in pairs(base) do
            if type(key) == "string" and key:sub(1, 2) == "__" and meta[key] == nil then
                meta[key] = value
            end
        end
    end
    meta.__index = function(_, key)
        local value = fields[key]
        if value == nil and fallback ~= nil then
            value = inherited(fallback, object, key)
            if type(value) == "function" then
                return value
            end
        end
        local node = scope.current
        if node then
            local watching = readers[key]
            if not watching then
                watching = state.readers()
                readers[key] = watching
            end
            watching[node] = true
        end
        return value
    end
    meta.__newindex = function(_, key, value)
        if rawequal(fields[key], value) then
            return
        end
        fields[key] = value
        local watching = readers[key]
        if watching then
            state.notify(watching)
        end
    end
    meta.__pairs = function()
        return next, fields, nil
    end
    return setmetatable(object, meta)
end
