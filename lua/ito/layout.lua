local M = {}

local function vertical(split)
    return split == "top" or split == "bottom"
end

function M.rect(x, y, width, height)
    return { x = x, y = y, width = math.max(width, 0), height = math.max(height, 0) }
end

local rect = M.rect

local function carve(area, split, take)
    if split == "top" then
        return rect(area.x, area.y, area.width, take), rect(area.x, area.y + take, area.width, area.height - take)
    end
    if split == "bottom" then
        local height = math.max(area.height - take, 0)
        return rect(area.x, area.y + height, area.width, take), rect(area.x, area.y, area.width, height)
    end
    if split == "left" then
        return rect(area.x, area.y, take, area.height), rect(area.x + take, area.y, area.width - take, area.height)
    end
    local width = math.max(area.width - take, 0)
    return rect(area.x + width, area.y, take, area.height), rect(area.x, area.y, width, area.height)
end

local function resolve(extent, available)
    if extent.percent then
        return math.floor(available * math.min(extent.percent, 100) / 100)
    end
    return math.min(extent.cells, available)
end

function M.centered(area, width, height)
    width = math.min(width, area.width)
    height = math.min(height, area.height)
    return rect(area.x + math.floor((area.width - width) / 2), area.y + math.floor((area.height - height) / 2), width, height)
end

function M.float(area, float)
    return M.centered(area, resolve(float.width, area.width), resolve(float.height, area.height))
end

function M.dock(area, items)
    local rects = {}
    local remaining = area
    for index, item in ipairs(items) do
        if item.float then
            rects[index] = M.float(area, item.float)
        else
            local down = vertical(item.split)
            local reserved, fills = 0, 1
            for later = index + 1, #items do
                local other = items[later]
                if not other.float and vertical(other.split) == down then
                    if type(other.extent) == "number" then
                        reserved = reserved + other.extent
                    else
                        fills = fills + 1
                    end
                end
            end
            local available = down and remaining.height or remaining.width
            local take
            if type(item.extent) == "number" then
                take = math.min(item.extent, available)
            else
                take = math.floor(math.max(available - reserved, 0) / fills)
            end
            rects[index], remaining = carve(remaining, item.split, take)
        end
    end
    return rects
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

return M
