local M = {}

M.Placement = {
    top_bar_leading = { name = "top_bar_leading" },
    top_bar_trailing = { name = "top_bar_trailing" },
    keyboard = { name = "keyboard" },
    bottom_bar = { name = "bottom_bar" },
}

local KNOWN = {}
for _, placement in pairs(M.Placement) do
    KNOWN[placement] = true
end

function M.is(value)
    return KNOWN[value] == true
end

return M
