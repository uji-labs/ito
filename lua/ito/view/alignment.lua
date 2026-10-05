local M = {}

M.Alignment = {
    top_leading = { x = 0, y = 0 },
    top = { x = 0.5, y = 0 },
    top_trailing = { x = 1, y = 0 },
    leading = { x = 0, y = 0.5 },
    center = { x = 0.5, y = 0.5 },
    trailing = { x = 1, y = 0.5 },
    bottom_leading = { x = 0, y = 1 },
    bottom = { x = 0.5, y = 1 },
    bottom_trailing = { x = 1, y = 1 },
}

local ALIGNED = {}
for _, alignment in pairs(M.Alignment) do
    ALIGNED[alignment] = true
end

local function alignment_of(value, what)
    if value == nil then
        return M.Alignment.center
    end
    if not ALIGNED[value] then
        error(what .. " takes one of ito.Alignment", 3)
    end
    return value
end

M.of = alignment_of

function M.is(value)
    return ALIGNED[value] == true
end

return M
