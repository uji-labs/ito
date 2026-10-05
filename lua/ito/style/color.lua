local M = {}

local NAMES = {
    "black",
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "gray",
    "dark_gray",
    "light_red",
    "light_green",
    "light_yellow",
    "light_blue",
    "light_magenta",
    "light_cyan",
}

local INDEXES = 255

local specs, made = {}, {}

local Color = {
    __name = "ito.Color",
    __metatable = "ito.Color",
}

function Color.__index(color, key)
    if key == "spec" then
        return specs[color]
    end
end

function Color.__newindex()
    error("an ito.Color cannot change", 2)
end

function Color.__tostring(color)
    return specs[color]
end

local function make(spec)
    local found = made[spec]
    if not found then
        found = setmetatable({}, Color)
        specs[found] = spec
        made[spec] = found
    end
    return found
end

M.Color = {}

for _, name in ipairs(NAMES) do
    M.Color[name] = make(name)
end

function M.Color.indexed(number)
    if type(number) ~= "number" or number % 1 ~= 0 or number < 0 or number > INDEXES then
        error("ito.Color.indexed takes a whole number from 0 to " .. INDEXES .. ", not " .. tostring(number), 2)
    end
    return make(string.format("%d", number))
end

function M.rgb(value)
    if type(value) ~= "number" or value < 0 or value > 0xffffff or value % 1 ~= 0 then
        error("ito.rgb takes a colour such as 0xd4d4d4", 2)
    end
    return make(string.format("#%06x", value))
end

function M.is(value)
    return specs[value] ~= nil
end

function M.check(value, what, level)
    if specs[value] == nil then
        error(what .. " must be an ito.Color, not a " .. type(value), (level or 2) + 1)
    end
    return value
end

return M
