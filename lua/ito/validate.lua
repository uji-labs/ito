local M = {}

local function numeric(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function M.finite(value, name)
    if not numeric(value) then
        error(name .. " must be a finite number", 3)
    end
    return value
end

function M.number(value, low, high, name)
    if not numeric(value) or value < low or value > high then
        error(name .. " must be a number between " .. low .. " and " .. high, 3)
    end
    return value
end

function M.whole(value, low, high, name)
    if not numeric(value) or value % 1 ~= 0 or value < low or value > high then
        error(name .. " must be a whole number between " .. low .. " and " .. high, 3)
    end
    return value
end

function M.choice(value, values, name)
    for _, option in pairs(values) do
        if value == option then
            return value
        end
    end
    error(name .. " needs one of the allowed values", 3)
end

return M
