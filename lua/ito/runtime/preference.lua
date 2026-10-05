local M = {}

local Preference = {}

function M.PreferenceKey(spec)
    if type(spec) ~= "table" or type(spec.reduce) ~= "function" then
        error("ito.PreferenceKey takes { default = value, reduce = function(value, next_value) }", 2)
    end
    return setmetatable({ default = spec.default, reduce = spec.reduce }, Preference)
end

function M.is_preference(value)
    return getmetatable(value) == Preference
end

local function gather(view, key, value)
    for _, reported in ipairs(view.reported or {}) do
        if reported.key == key then
            value = key.reduce(value, reported.value)
        end
    end
    for _, child in ipairs(view.composed or {}) do
        value = gather(child, key, value)
    end
    for _, extra in ipairs(view.extras or {}) do
        if extra.view then
            value = gather(extra.view, key, value)
        end
    end
    return value
end

function M.merged(view, key)
    return gather(view, key, key.default)
end

return M
