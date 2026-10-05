local M = {}

function M.rect(x, y, width, height)
    return { x = x, y = y, width = math.max(width, 0), height = math.max(height, 0) }
end

local rect = M.rect

function M.centered(area, width, height)
    width = math.min(width, area.width)
    height = math.min(height, area.height)
    return rect(area.x + math.floor((area.width - width) / 2), area.y + math.floor((area.height - height) / 2), width, height)
end

function M.stack(area, extents, down)
    local total = down and area.height or area.width
    local used, weights = 0, 0
    for _, extent in ipairs(extents) do
        if type(extent) == "number" then
            used = used + extent
        else
            weights = weights + extent.weight
        end
    end
    local spare = math.max(total - used, 0)
    local rects, at = {}, down and area.y or area.x
    local finish = at + total
    for index, extent in ipairs(extents) do
        local take = extent
        if type(extent) ~= "number" then
            take = weights > 0 and math.floor(spare * extent.weight / weights) or 0
            spare, weights = spare - take, weights - extent.weight
        end
        take = math.max(math.min(take, finish - at), 0)
        if down then
            rects[index] = rect(area.x, at, area.width, take)
        else
            rects[index] = rect(at, area.y, take, area.height)
        end
        at = at + take
    end
    return rects
end

function M.inner(area, border, padding)
    local x, y, width, height = area.x, area.y, area.width, area.height
    if border == "plain" or border == "rounded" then
        x, y, width, height = x + 1, y + 1, width - 2, height - 2
    elseif border == "horizontal" then
        y, height = y + 1, height - 2
    end
    padding = padding or 0
    return rect(x, y + padding, width, height - padding * 2)
end

function M.clamp(value, low, high)
    return math.max(math.min(value, high), low)
end

return M
