local class = require("ito.class")
local helpers = require("ito.theme.helpers")
local host = require("ito.host")
local schema = require("ito.theme.schema")

local revisions = 0

local function revise()
    revisions = revisions + 1
    return revisions
end

local function merge(layers)
    local merged = {}
    for _, group in ipairs(schema.GROUPS) do
        local into = {}
        for _, layer in ipairs(layers) do
            for key, value in pairs(layer[group] or {}) do
                into[key] = value
            end
        end
        merged[group] = into
    end
    return merged
end

local Theme = class()

Theme.color = schema.color

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

function Theme:chain(selection, seen, layers)
    local spec = type(selection) == "string" and self:load(selection) or selection
    local name = type(selection) == "string" and selection or spec.name
    local label = name and "theme " .. name or "theme"
    if seen[spec] then
        error(label .. " extends itself", 0)
    end
    seen[spec] = true
    schema.check(spec, label)
    if spec ~= self.default then
        self:chain(spec.extends or self.default.name, seen, layers)
    end
    layers[#layers + 1] = spec
    return layers
end

function Theme:build(selection)
    return schema.resolve(merge(self:chain(selection, {}, {})), self.default, "theme")
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

function Theme:element(ctx, name, data, width)
    ctx.width = width
    local ok, lines = pcall(ctx.templates[name], ctx, data)
    if ok and type(lines) == "table" then
        self.reported[name] = nil
        return lines
    end
    local problem = ok and "returned a " .. type(lines) .. " instead of lines" or tostring(lines)
    if self.reported[name] ~= problem then
        self.reported[name] = problem
        host.report("theme " .. name .. ": " .. problem)
    end
    ctx.width = width
    return self.default.templates[name](ctx, data)
end

function Theme:context(styles)
    if self.built == self.revision then
        return self.ctx
    end
    local tokens = self.tokens
    local ids = styles:resolve(tokens.roles)
    self.built = self.revision
    self.reported = self.reported or {}
    self.ctx = {
        style = setmetatable({}, {
            __index = function(_, role)
                local id = ids[role]
                if id == nil then
                    error("unknown role " .. tostring(role), 2)
                end
                return id
            end,
        }),
        colors = tokens.colors,
        symbols = tokens.symbols,
        borders = tokens.borders,
        text = tokens.text,
        limits = tokens.limits,
        options = tokens.options,
        templates = tokens.templates,
    }
    for name, helper in pairs(helpers) do
        self.ctx[name] = helper
    end
    self.ctx.element = function(ctx, name, data, width)
        return self:element(ctx, name, data, width)
    end
    self.ctx.with = function(_, id, role)
        local spec = tokens.roles[role]
        if not spec then
            error("unknown role " .. tostring(role), 2)
        end
        return styles:with(id, spec)
    end
    return self.ctx
end

return Theme
