local color = require("ito.style.color")

local M = {}

local FLAGS = { "bold", "dim", "italic", "underline", "reverse", "strikethrough", "blink" }

M.FLAGS = FLAGS

local FLAG = {}
for _, flag in ipairs(FLAGS) do
    FLAG[flag] = true
end

local TextStyle = {}
TextStyle.__index = TextStyle

function TextStyle.__newindex()
    error("an ito.TextStyle cannot change; merge makes a new one", 2)
end

local made, merges = {}, {}
local count = 0

local function key(fields)
    local parts = {
        fields.foreground and fields.foreground.spec or "",
        fields.background and fields.background.spec or "",
    }
    for _, flag in ipairs(FLAGS) do
        parts[#parts + 1] = fields[flag] and "1" or "0"
    end
    return table.concat(parts, "|")
end

local function intern(fields)
    local name = key(fields)
    local found = made[name]
    if not found then
        count = count + 1
        found = { id = count, foreground = fields.foreground, background = fields.background }
        for _, flag in ipairs(FLAGS) do
            found[flag] = fields[flag] or nil
        end
        made[name] = setmetatable(found, TextStyle)
    end
    return found
end

local function new(fields)
    if fields == nil then
        return intern({})
    end
    if type(fields) ~= "table" then
        error("ito.TextStyle takes a table of fields, not a " .. type(fields), 3)
    end
    for name, value in pairs(fields) do
        if name == "foreground" or name == "background" then
            color.check(value, "a TextStyle's " .. name, 3)
        elseif not FLAG[name] then
            error("a TextStyle has foreground, background, " .. table.concat(FLAGS, ", ") .. ", not " .. tostring(name), 3)
        elseif type(value) ~= "boolean" then
            error("a TextStyle's " .. name .. " must be true or false, not a " .. type(value), 3)
        end
    end
    return intern(fields)
end

function TextStyle:merge(other)
    if other == nil then
        return self
    end
    if getmetatable(other) ~= TextStyle then
        error("merge takes an ito.TextStyle, not a " .. type(other), 2)
    end
    local cache = merges[self]
    if not cache then
        cache = {}
        merges[self] = cache
    end
    local found = cache[other]
    if not found then
        local fields = {
            foreground = other.foreground or self.foreground,
            background = other.background or self.background,
        }
        for _, flag in ipairs(FLAGS) do
            fields[flag] = other[flag] or self[flag]
        end
        found = intern(fields)
        cache[other] = found
    end
    return found
end

M.TextStyle = setmetatable({}, {
    __call = function(_, fields)
        return new(fields)
    end,
})

M.plain = intern({})

function M.is(value)
    return getmetatable(value) == TextStyle
end

function M.check(value, what, level)
    if getmetatable(value) ~= TextStyle then
        error(what .. " must be an ito.TextStyle, not a " .. type(value), (level or 2) + 1)
    end
    return value
end

return M
