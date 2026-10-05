local class = require("ito.class")
local layout = require("ito.layout")
local schema = require("ito.theme.schema")
local text = require("ito.text")
local View = require("ito.view")

local M = {}

local Side = View.Side
local LATER = { [Side.bottom] = true, [Side.right] = true }

local function vertical(side)
    return side == Side.top or side == Side.bottom
end

local function insert(list, anchor, item, spot)
    local at
    for index, child in ipairs(list) do
        if child == anchor then
            at = index
            break
        end
    end
    local index
    if spot.before then
        index = spot.prepend and at - spot.count or at
    else
        index = spot.prepend and at + 1 or at + spot.count + 1
    end
    table.insert(list, index, item)
end

local FLAGS = schema.FLAGS

local function widest(rows)
    local most = 0
    for _, line in ipairs(rows) do
        local used = 0
        for _, span in ipairs(line) do
            used = used + text.width(span[1])
        end
        most = math.max(most, used)
    end
    return most
end

local function stacked(view, frame, down)
    local inner = view.inner
    local extents = {}
    for index, child in ipairs(view.composed) do
        extents[index] = child:extent(frame, inner, down)
    end
    local rects = layout.stack(inner, extents, down)
    for index, child in ipairs(view.composed) do
        child:place(frame, rects[index])
    end
end

local VStack = class(View)
M.VStack = VStack

function VStack:content_height(frame, width)
    local total = 0
    for _, child in ipairs(self.composed or {}) do
        if not child.weight and not child.fraction then
            total = total + (child.fixed_height or child:measure(frame, width))
        end
    end
    return total
end

function VStack:arrange(frame)
    stacked(self, frame, true)
end

local HStack = class(View)
M.HStack = HStack

function HStack:content_height(frame, width)
    local most = 0
    for _, child in ipairs(self.composed or {}) do
        most = math.max(most, child:measure(frame, width))
    end
    return most
end

function HStack:content_width(frame)
    local total = 0
    for _, child in ipairs(self.composed or {}) do
        local used = child.fixed_width or child:natural_width(frame)
        if not used then
            return nil
        end
        total = total + used
    end
    return total
end

function HStack:arrange(frame)
    stacked(self, frame, false)
end

local function beside(container, item, anchor, toward)
    local wrap = (vertical(toward) and VStack or HStack)({})
    wrap.composed = { anchor }
    wrap.side, wrap.weight, wrap.fraction = anchor.side, anchor.weight, anchor.fraction
    wrap.fixed_height, wrap.fixed_width = anchor.fixed_height, anchor.fixed_width
    for index, child in ipairs(container.composed) do
        if child == anchor then
            container.composed[index] = wrap
        end
    end
    return wrap:adopt(item, anchor, toward, 0)
end

function VStack:adopt(item, anchor, toward, count)
    if not vertical(toward) then
        return beside(self, item, anchor, toward)
    end
    insert(self.composed, anchor, item, { before = toward == Side.top, count = count })
    return true
end

function HStack:adopt(item, anchor, toward, count)
    if vertical(toward) then
        return beside(self, item, anchor, toward)
    end
    insert(self.composed, anchor, item, { before = toward == Side.left, count = count })
    return true
end

local Spacer = class(View)
M.Spacer = Spacer

function Spacer:init()
    View.init(self, {})
    self.weight = 1
end

local Text = class(View)
M.Text = Text

function Text:init(content)
    View.init(self, {})
    if type(content) ~= "string" then
        error("Text takes a string, not a " .. type(content), 3)
    end
    self.content = content
    self.spec = {}
end

for _, flag in ipairs(FLAGS) do
    Text[flag] = function(self)
        self.spec[flag] = true
        return self
    end
end

function Text:foreground(color)
    self.spec.fg = schema.color(color)
    return self
end

function Text:rows(frame)
    local style = next(self.spec) and frame.styles:get(self.spec) or 0
    local rows = {}
    for index, line in ipairs(text.lines(self.content)) do
        rows[index] = { { line, style } }
    end
    return rows
end

function Text:content_height()
    return #text.lines(self.content)
end

function Text:content_width(frame)
    return widest(self:rows(frame))
end

function Text:draw_content(frame)
    frame:lines(self.inner, self:rows(frame))
end

local Lines = class(View)
M.Lines = Lines

function Lines:init(rows)
    View.init(self, {})
    if type(rows) ~= "table" then
        error("Lines takes a list of lines, not a " .. type(rows), 3)
    end
    self.rows = rows
end

function Lines:content_height()
    return #self.rows
end

function Lines:content_width()
    return widest(self.rows)
end

function Lines:draw_content(frame)
    frame:lines(self.inner, self.rows)
end

local Dock = class(View)
M.Dock = Dock

function Dock:arrange(frame, inner)
    local items = self.composed
    local entries, natural = {}, {}
    for index, item in ipairs(items) do
        local split = item.side or Side.top
        local down = vertical(split)
        local total = down and inner.height or inner.width
        local fixed = down and item.fixed_height or item.fixed_width
        local extent = fixed
        if not extent and item.fraction then
            extent = math.floor(total * item.fraction)
        elseif not extent and item.weight then
            extent = "fill"
        elseif not extent then
            extent = 0
            natural[index] = true
        end
        entries[index] = { split = split, float = item.floating, extent = extent }
    end
    local rects = layout.dock(inner, entries)
    for index, item in ipairs(items) do
        if natural[index] then
            entries[index].extent = item:measure(frame, rects[index].width)
        end
    end
    rects = layout.dock(inner, entries)
    for index, item in ipairs(items) do
        item:place(frame, rects[index])
    end
    self.items = items
end

function Dock:adopt(item, anchor, toward, count)
    local side = anchor.side or Side.top
    if vertical(side) ~= vertical(toward) then
        return beside(self, item, anchor, toward)
    end
    item.side = side
    insert(self.composed, anchor, item, { before = toward == side, prepend = LATER[side], count = count })
    return true
end

function Dock:draw(frame)
    if self:framed() then
        frame:chrome(self)
    end
    for _, floating in ipairs({ false, true }) do
        for _, item in ipairs(self.items or {}) do
            if (item.floating ~= nil) == floating then
                item:draw(frame)
            end
        end
    end
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

local Anchor = class()

function Anchor:init(toward, id)
    if id == nil then
        error("an anchor needs the id of a view, or a view class", 3)
    end
    self.toward = toward
    self.id = id
end

function M.above(id)
    return Anchor(Side.top, id)
end

function M.below(id)
    return Anchor(Side.bottom, id)
end

function M.left_of(id)
    return Anchor(Side.left, id)
end

function M.right_of(id)
    return Anchor(Side.right, id)
end

function M.is_anchor(value)
    return getmetatable(value) == Anchor
end

local function find(parent, id)
    for _, child in ipairs(parent.composed or {}) do
        if child.key == id or getmetatable(child) == id then
            return parent, child
        end
        local found, anchor = find(child, id)
        if found then
            return found, anchor
        end
    end
end

function M.attach(root, entries)
    local counts, missed = {}, {}
    for _, entry in ipairs(entries) do
        local toward, id = entry.anchor.toward, entry.anchor.id
        local parent, target = find(root, id)
        local group = target and (counts[target] or {})
        local count = group and group[toward] or 0
        if parent and parent.adopt and parent:adopt(entry.view, target, toward, count) then
            counts[target] = group
            group[toward] = count + 1
        else
            missed[#missed + 1] = entry
        end
    end
    return missed
end

return M
