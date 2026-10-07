local class = require("ito.class")
local helpers = require("ito.theme.helpers")
local schema = require("ito.theme.schema")
local text_style = require("ito.style.text_style")

local revisions = 0

local function revise()
    revisions = revisions + 1
    return revisions
end

local Theme = class()

function Theme:init(opts)
    self.default = opts.default
    self.loader = opts.load
    self.selection = self.default.name
    self.tokens = self:build(self.selection)
    self.revision = revise()
end

function Theme:load(name)
    if name == self.default.name then
        return self.default
    end
    local found = self.loader(name)
    if type(found) ~= "table" then
        error("theme " .. name .. " must return a table", 0)
    end
    return found
end

function Theme:build(selection)
    local theme = type(selection) == "string" and self:load(selection) or selection
    local name = type(selection) == "string" and selection or type(theme) == "table" and theme.name
    return schema.check(theme, self.default, type(name) == "string" and "theme " .. name or "theme")
end

function Theme:use(selection, tokens)
    self.selection, self.tokens = selection, tokens
    self.revision = revise()
end

function Theme:select(selection)
    self:use(selection, self:build(selection))
end

function Theme:bump()
    self.revision = revise()
end

local function strict(values, prefix)
    local copy = {}
    for name, value in pairs(values) do
        copy[name] = text_style.is(value) and value or strict(value, prefix .. name .. ".")
    end
    return setmetatable(copy, {
        __index = function(_, name)
            error("the theme has no style named " .. prefix .. tostring(name), 2)
        end,
    })
end

function Theme:context()
    if self.built == self.revision then
        return self.ctx
    end
    local tokens = self.tokens
    self.built = self.revision
    self.ctx = {
        styles = strict(tokens.styles, ""),
        colors = tokens.colors,
        symbols = tokens.symbols,
        borders = tokens.borders,
        text = tokens.text,
        limits = tokens.limits,
        options = tokens.options,
        views = tokens.views,
    }
    for name, helper in pairs(helpers) do
        self.ctx[name] = helper
    end
    return self.ctx
end

return Theme
