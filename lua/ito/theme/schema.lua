local M = {}

local NAMED = {
    black = true,
    red = true,
    green = true,
    yellow = true,
    blue = true,
    magenta = true,
    cyan = true,
    white = true,
    gray = true,
    grey = true,
    dark_gray = true,
    dark_grey = true,
    light_red = true,
    light_green = true,
    light_yellow = true,
    light_blue = true,
    light_magenta = true,
    light_cyan = true,
}

local INDEXES = 255
local REFERENCE = "^{palette%.([%w_]+)}$"

local FLAGS = { "bold", "dim", "italic", "underline", "reverse", "strikethrough", "blink" }

local FLAG = {}
for _, flag in ipairs(FLAGS) do
    FLAG[flag] = true
end

local PALETTE = {}
for index = 0, 15 do
    PALETTE[string.format("base%02X", index)] = true
end

local GROUPS = { "palette", "colors", "roles", "symbols", "borders", "text", "limits", "options", "templates" }

local EDGES = { "top_left", "top_right", "bottom_left", "bottom_right", "horizontal", "vertical" }

M.GROUPS = GROUPS

local function fail(path, message)
    error(path .. ": " .. message, 0)
end

function M.color(value)
    if type(value) == "number" then
        if value % 1 ~= 0 or value < 0 or value > INDEXES then
            error("a colour number must be a whole number from 0 to " .. INDEXES .. ", not " .. value, 0)
        end
        return tostring(value)
    end
    if type(value) ~= "string" then
        error("a colour must be a string or a number, not a " .. type(value), 0)
    end
    if value:sub(1, 1) == "#" then
        if not value:match("^#%x%x%x%x%x%x$") then
            error("invalid color: " .. value .. " (expected #rrggbb)", 0)
        end
        return value
    end
    local index = tonumber(value:match("^%d+$"))
    if index then
        return M.color(index)
    end
    if not NAMED[value] then
        error("unknown color: " .. value, 0)
    end
    return value
end

local function literal(value, path)
    local ok, found = pcall(M.color, value)
    if not ok then
        fail(path, found)
    end
    return found
end

local function table_at(value, path)
    if type(value) ~= "table" then
        fail(path, "must be a table, not a " .. type(value))
    end
    return value
end

local function each(group, path, check)
    for key, value in pairs(table_at(group, path)) do
        if type(key) ~= "string" then
            fail(path, "keys must be names, not " .. tostring(key))
        end
        check(key, value, path .. "." .. key)
    end
end

local CHECKS = {
    palette = function(key, value, path)
        if not PALETTE[key] then
            fail(path, "a palette has base00 to base0F only")
        end
        literal(value, path)
    end,
    colors = function(_, value, path)
        if type(value) == "string" and value:match(REFERENCE) then
            return
        end
        literal(value, path)
    end,
    roles = function(_, value, path)
        for key, setting in pairs(table_at(value, path)) do
            if key == "fg" or key == "bg" then
                if type(setting) ~= "string" and type(setting) ~= "number" then
                    fail(path .. "." .. key, "must name a colour")
                end
            elseif type(setting) ~= "boolean" or not FLAG[key] then
                fail(path .. "." .. tostring(key), "a role has fg, bg and the flags " .. table.concat(FLAGS, ", "))
            end
        end
    end,
    symbols = function(_, value, path)
        if type(value) == "table" then
            for index, item in ipairs(value) do
                if type(item) ~= "string" then
                    fail(path .. "[" .. index .. "]", "must be a string")
                end
            end
            return
        end
        if type(value) ~= "string" then
            fail(path, "must be a string or a list of strings")
        end
    end,
    borders = function(_, value, path)
        local given = table_at(value, path)
        for _, edge in ipairs(EDGES) do
            if type(given[edge]) ~= "string" then
                fail(path .. "." .. edge, "must be a string")
            end
        end
        for key in pairs(given) do
            local known = false
            for _, edge in ipairs(EDGES) do
                known = known or edge == key
            end
            if not known then
                fail(path .. "." .. tostring(key), "a border has " .. table.concat(EDGES, ", "))
            end
        end
    end,
    text = function(_, value, path)
        if type(value) ~= "string" then
            fail(path, "must be a string")
        end
    end,
    limits = function(_, value, path)
        if type(value) ~= "number" or value < 0 then
            fail(path, "must be a number that is not negative")
        end
    end,
    options = function() end,
    templates = function(_, value, path)
        if type(value) ~= "function" then
            fail(path, "must be a function")
        end
    end,
}

function M.check(spec, path)
    table_at(spec, path)
    for key, value in pairs(spec) do
        local at = path .. "." .. tostring(key)
        if key == "name" or key == "extends" then
            if type(value) ~= "string" then
                fail(at, "must be a string")
            end
        elseif CHECKS[key] then
            each(value, at, CHECKS[key])
        else
            fail(at, "a theme has name, extends, " .. table.concat(GROUPS, ", "))
        end
    end
end

local function shade(value, colors, path)
    local name = type(value) == "string" and colors[value]
    if name then
        return name
    end
    return literal(value, path)
end

function M.resolve(merged, known, path)
    local palette = {}
    for slot, value in pairs(merged.palette) do
        palette[slot] = literal(value, path .. ".palette." .. slot)
    end
    local colors = {}
    for name, value in pairs(merged.colors) do
        local slot = type(value) == "string" and value:match(REFERENCE)
        if slot then
            colors[name] = palette[slot] or fail(path .. ".colors." .. name, "the palette has no " .. slot)
        else
            colors[name] = literal(value, path .. ".colors." .. name)
        end
    end
    local roles = {}
    for name, role in pairs(merged.roles) do
        local spec = {}
        for key, setting in pairs(role) do
            if key == "fg" or key == "bg" then
                spec[key] = shade(setting, colors, path .. ".roles." .. name .. "." .. key)
            elseif setting then
                spec[key] = true
            end
        end
        roles[name] = spec
    end
    for _, group in ipairs({ "symbols", "borders", "text", "limits", "templates" }) do
        for key in pairs(merged[group]) do
            local namespaced = group == "templates" and key:find(".", 1, true)
            if known[group][key] == nil and not namespaced then
                fail(path .. "." .. group .. "." .. key, "the default theme has no " .. group:gsub("s$", "") .. " named " .. key)
            end
        end
    end
    return {
        colors = colors,
        roles = roles,
        symbols = merged.symbols,
        borders = merged.borders,
        text = merged.text,
        limits = merged.limits,
        options = merged.options,
        templates = merged.templates,
    }
end

return M
