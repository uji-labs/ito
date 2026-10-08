local class = require("ito.class")
local layout = require("ito.layout")
local stack = require("ito.views.stack")
local View = require("ito.view")

local HStack, VStack = stack.HStack, stack.VStack

local GridRow = class(HStack)

local function cells(row)
    return row.composed or row.children
end

function GridRow:content_height(frame, width)
    local columns = self.columns
    if not columns then
        return HStack.content_height(self, frame, width)
    end
    local most = 0
    for index, cell in ipairs(cells(self)) do
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

local function standalone(row)
    if getmetatable(row) ~= GridRow then
        return row.standalone == true
    end
    for _, cell in ipairs(row.children) do
        if not cell.standalone then
            return false
        end
    end
    return true
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
    for at = 1, #grid.children do
        local row = grid:row(at)
        if getmetatable(row) == GridRow then
            for index, cell in ipairs(cells(row)) do
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
    for at = 1, #grid.children do
        local row = grid:row(at)
        if getmetatable(row) == GridRow then
            row.columns, row.rect = known.columns, nil
        end
    end
    return known
end

local Grid = class(VStack)

function Grid:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    self.generation = composition.generation
    self.made, self.built = {}, {}
    return self
end

function Grid:row(index)
    local made = self.made[index]
    if made == nil then
        local element = self.children[index]
        if standalone(element) then
            made = element
        else
            made = self.composition:place(element, self.node, index, self.environment) or false
            if made then
                self.built[#self.built + 1] = made
            end
        end
        self.made[index] = made
    end
    return made or nil
end

function Grid:steady()
    for _, row in ipairs(self.built) do
        if not row:steady() then
            return false
        end
    end
    for _, extra in ipairs(self.extras or {}) do
        if extra.view and not extra.view:steady() then
            return false
        end
    end
    return true
end

function Grid:content_height(frame, width)
    local known = fitted(self, frame, width)
    if not known.height then
        local tops, heights, total, shown = {}, {}, 0, false
        for index = 1, #self.children do
            local row = self:row(index)
            if row and not row.is_hidden then
                total = total + (shown and self.gap or 0)
                shown = true
            end
            tops[index], heights[index] = total, row and row:measure(frame, width) or 0
            total = total + heights[index]
        end
        known.tops, known.heights, known.height = tops, heights, total
    end
    return known.height
end

function Grid:arrange(frame, inner)
    self:content_height(frame, inner.width)
end

local function first(tops, offset)
    local low, high = 1, #tops
    while low < high do
        local middle = math.ceil((low + high) / 2)
        if tops[middle] <= offset then
            low = middle
        else
            high = middle - 1
        end
    end
    return low
end

function Grid:paint(frame)
    if self.fill then
        frame:fill(self:surface(), self.fill)
    end
    if self:framed() then
        frame:chrome(self)
    end
    local inner, known = self.inner, self.known
    local top, bottom = inner.y, inner.y + inner.height
    local clip = frame.clipping
    if clip then
        top, bottom = math.max(top, clip.y), math.min(bottom, clip.y + clip.height)
    end
    local tops, heights = known.tops, known.heights
    local index = first(tops, top - inner.y)
    while index <= #tops and inner.y + tops[index] < bottom do
        local row = self.composition:place(self.children[index], self.node, index, self.environment)
        if row then
            row:place(frame, layout.rect(inner.x, inner.y + tops[index], inner.width, heights[index]))
            row:draw(frame)
        end
        index = index + 1
    end
    if self.generation == self.composition.generation then
        self.node:sweep(self.generation)
    end
    self:draw_extras(frame)
    if self.click then
        frame:clickable(self:surface(), self.click)
    end
end

return { Grid = Grid, GridRow = GridRow }
