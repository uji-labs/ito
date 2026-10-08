local class = require("ito.class")
local layout = require("ito.layout")
local stack = require("ito.views.stack")
local View = require("ito.view")

local HStack, VStack = stack.HStack, stack.VStack

local GridRow = class(HStack)

function GridRow:content_height(frame, width)
    local columns = self.columns
    if not columns then
        return HStack.content_height(self, frame, width)
    end
    local most = 0
    for index, cell in ipairs(self.composed or {}) do
        most = math.max(most, cell:measure(frame, columns[index].width))
    end
    return most
end

function GridRow:arrange(frame, inner)
    local columns = self.columns
    if not columns then
        return HStack.arrange(self, frame, inner)
    end
    for index, cell in ipairs(self.composed) do
        local column = columns[index]
        local area = layout.rect(inner.x + column.x, inner.y, column.width, inner.height)
        cell:place(frame, cell.aligned and View.fit(frame, cell, area, cell.aligned) or area)
    end
end

local function level(widths, room)
    local sorted = {}
    for _, width in pairs(widths) do
        sorted[#sorted + 1] = width
    end
    table.sort(sorted)
    for index, width in ipairs(sorted) do
        local left = #sorted - index + 1
        if width * left > room then
            return math.floor(math.max(room, 0) / left)
        end
        room = room - width
    end
    return math.huge
end

local function columns(grid, frame, width)
    local room = layout.rect(0, 0, width, 0)
    local widest, weights, shrinks, count = {}, {}, {}, 0
    for _, row in ipairs(grid.composed or {}) do
        if getmetatable(row) == GridRow then
            for index, cell in ipairs(row.composed or {}) do
                count = math.max(count, index)
                local extent = cell:extent(frame, room, false)
                if type(extent) ~= "number" then
                    weights[index] = math.max(weights[index] or 0, extent.weight)
                    extent = cell.shrinks and cell:natural_width(frame) or 0
                end
                widest[index] = math.max(widest[index] or 0, extent)
                shrinks[index] = shrinks[index] or cell.shrinks
            end
        end
    end
    local fixed, narrowing = 0, {}
    for index = 1, count do
        if shrinks[index] then
            narrowing[index] = widest[index] or 0
        elseif not weights[index] then
            fixed = fixed + (widest[index] or 0)
        end
    end
    local cap = level(narrowing, width - fixed)
    local extents = {}
    for index = 1, count do
        if weights[index] then
            extents[index] = { weight = weights[index] }
        else
            extents[index] = math.min(widest[index] or 0, shrinks[index] and cap or math.huge)
        end
    end
    return layout.stack(room, extents, false)
end

local function fitted(grid, frame, width)
    local known = grid.known
    if known and known.width == width and grid:steady() then
        return known
    end
    known = { width = width, columns = columns(grid, frame, width) }
    grid.known = known
    for _, row in ipairs(grid.composed or {}) do
        if getmetatable(row) == GridRow then
            row.columns, row.rect = known.columns, nil
        end
    end
    return known
end

local Grid = class(VStack)

function Grid:content_height(frame, width)
    local known = fitted(self, frame, width)
    if not known.height then
        known.height = VStack.content_height(self, frame, width)
    end
    return known.height
end

function Grid:arrange(frame, inner)
    fitted(self, frame, inner.width)
    VStack.arrange(self, frame, inner)
end

return { Grid = Grid, GridRow = GridRow }
