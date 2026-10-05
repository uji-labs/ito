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

local Color = {}

function Color.__tostring(color)
    return color.spec
end

function Color.__newindex()
    error("an ito.Color cannot change", 2)
end

local made = {}

local function make(spec)
    local found = made[spec]
    if not found then
        found = setmetatable({ spec = spec }, Color)
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
    return make(tostring(number))
end

function M.rgb(value)
    if type(value) ~= "number" or value < 0 or value > 0xffffff or value % 1 ~= 0 then
        error("ito.rgb takes a colour such as 0xd4d4d4", 2)
    end
    return make(string.format("#%06x", value))
end

function M.is(value)
    return getmetatable(value) == Color
end

function M.check(value, what, level)
    if getmetatable(value) ~= Color then
        error(what .. " must be an ito.Color, not a " .. type(value), (level or 2) + 1)
    end
    return value
end

return M
