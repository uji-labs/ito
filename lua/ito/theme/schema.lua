local call = require("ito.runtime.call")
local color = require("ito.style.color")
local text_style = require("ito.style.text_style")

local M = {}

local GROUPS = { "colors", "styles", "symbols", "borders", "text", "limits", "options", "views" }

local OPEN = { colors = true, styles = true, options = true, views = true }

local SINGULAR = {
    colors = "color",
    styles = "style",
    symbols = "symbol",
    borders = "border",
    text = "text",
    limits = "limit",
}

local EDGES = { "top_left", "top_right", "bottom_left", "bottom_right", "horizontal", "vertical" }

M.GROUPS = GROUPS

local function fail(path, message)
    error(path .. ": " .. message, 0)
end

local function table_at(value, path)
    if type(value) ~= "table" then
        fail(path, "must be a table, not a " .. type(value))
    end
    return value
end

local function grouped(is, kind)
    return function(value, path, default)
        local group = type(value) == "table" and not is(value)
        if default ~= nil and group == is(default) then
            fail(path, group and "must be an " .. kind .. ", not a table" or "must be a table of " .. kind .. " values")
        end
        if not group then
            if not is(value) then
                fail(path, "must be an " .. kind .. ", not a " .. type(value))
            end
            return
        end
        for key, item in pairs(value) do
            if not is(item) then
                fail(path .. "." .. tostring(key), "must be an " .. kind .. ", not a " .. type(item))
            end
        end
        for key in pairs(default or {}) do
            if value[key] == nil then
                fail(path .. "." .. key, "must be set, as every theme has it")
            end
        end
    end
end

local CHECKS = {
    colors = grouped(color.is, "ito.Color"),
    styles = grouped(text_style.is, "ito.TextStyle"),
    symbols = function(value, path)
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
    borders = function(value, path)
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
    text = function(value, path)
        if type(value) ~= "string" then
            fail(path, "must be a string")
        end
    end,
    limits = function(value, path)
        if type(value) ~= "number" or value < 0 then
            fail(path, "must be a number that is not negative")
        end
    end,
    options = function() end,
    views = function(value, path)
        if type(value) ~= "function" then
            fail(path, "must be a function that returns a view")
        end
    end,
}

local function known(group, key, default)
    return OPEN[group] or default[group][key] ~= nil
end

function M.check(theme, default, path)
    table_at(theme, path)
    for key, value in pairs(theme) do
        local at = path .. "." .. tostring(key)
        if key == "name" then
            if type(value) ~= "string" then
                fail(at, "must be a string")
            end
        elseif not CHECKS[key] then
            fail(at, "a theme has name, " .. table.concat(GROUPS, ", "))
        end
    end
    for _, group in ipairs(GROUPS) do
        local at = path .. "." .. group
        local given = table_at(theme[group], at)
        for key, value in pairs(given) do
            if group == "views" then
                if not call.is_descriptor(key) then
                    fail(at, "keys must be views made with ito.view, not " .. tostring(key))
                end
                key = "view"
            elseif type(key) ~= "string" then
                fail(at, "keys must be names, not " .. tostring(key))
            end
            if not known(group, key, default) then
                fail(at .. "." .. key, "the default theme has no " .. SINGULAR[group] .. " named " .. key)
            end
            CHECKS[group](value, at .. "." .. key, default[group][key])
        end
        for key in pairs(default[group]) do
            if given[key] == nil then
                fail(at .. "." .. key, "must be set, as every theme has it")
            end
        end
    end
    return theme
end

return M
