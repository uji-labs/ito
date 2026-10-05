local class = require("ito.class")

local FLAGS = require("ito.theme.schema").FLAGS

local function key_of(spec)
    local parts = { spec.fg or "", spec.bg or "" }
    for _, flag in ipairs(FLAGS) do
        parts[#parts + 1] = spec[flag] and "1" or "0"
    end
    return table.concat(parts, "|")
end

local function merge(base, extra)
    local spec = {}
    for key, value in pairs(base) do
        spec[key] = value
    end
    for key, value in pairs(extra) do
        spec[key] = value
    end
    return spec
end

local Styles = class()

function Styles:init(screen)
    self.screen = screen
    self.ids = {}
    self.specs = { [0] = {} }
    self.derived = {}
end

function Styles:get(spec)
    if spec == nil then
        return 0
    end
    local key = key_of(spec)
    local id = self.ids[key]
    if not id then
        local clean = {}
        for _, flag in ipairs(FLAGS) do
            clean[flag] = spec[flag] or nil
        end
        clean.fg, clean.bg = spec.fg, spec.bg
        id = self.screen:style(clean)
        self.ids[key] = id
        self.specs[id] = clean
    end
    return id
end

function Styles:with(id, extra)
    id = id or 0
    local cache = self.derived[id]
    if not cache then
        cache = {}
        self.derived[id] = cache
    end
    local key = key_of(extra)
    local found = cache[key]
    if not found then
        found = self:get(merge(self.specs[id], extra))
        cache[key] = found
    end
    return found
end

function Styles:spec(id)
    return self.specs[id or 0] or {}
end

function Styles:resolve(roles)
    local ids = {}
    for name, spec in pairs(roles) do
        ids[name] = next(spec) == nil and 0 or self:get(spec)
    end
    return ids
end

return Styles
