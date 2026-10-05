local M = {}

local Tuple = {}

local function described(key)
    if getmetatable(key) ~= Tuple then
        return tostring(key)
    end
    local parts = {}
    for index = 1, key.n do
        parts[index] = tostring(key[index])
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

function M.identity(...)
    local count = select("#", ...)
    if count == 0 then
        error("an id needs a value", 3)
    end
    for index = 1, count do
        local value = (select(index, ...))
        if value == nil or value == false or value ~= value then
            error("an id cannot be nil, false or NaN", 3)
        end
    end
    if count == 1 then
        return (...)
    end
    return setmetatable({ n = count, ... }, Tuple)
end

M.Tuple = Tuple
M.described = described

return M
