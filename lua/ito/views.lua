local class = require("ito.class")
local layout = require("ito.layout")
local schema = require("ito.theme.schema")
local text = require("ito.text")
local View = require("ito.view")

local M = {}

local FLAGS = { "bold", "dim", "italic", "underline", "reverse", "strikethrough", "blink" }

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

local function ordered(items)
    for index, item in ipairs(items) do
        item.position = index
    end
    table.sort(items, function(a, b)
        local left, right = a.order or layout.PRIORITY, b.order or layout.PRIORITY
        if left ~= right then
            return left < right
        end
        return a.position < b.position
    end)
    return items
end

local Dock = class(View)
M.Dock = Dock

function Dock:arrange(frame, inner)
    local items = {}
    for _, child in ipairs(self.composed) do
        if child.expand then
            for _, item in ipairs(child:expand(frame)) do
                items[#items + 1] = item
            end
        else
            items[#items + 1] = child
        end
    end
    local entries, natural = {}, {}
    for index, item in ipairs(ordered(items)) do
        local split = item.side or View.Side.top
        local down = split == View.Side.top or split == View.Side.bottom
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
        entries[index] = { split = split, float = item.float, extent = extent }
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

function Dock:draw(frame)
    if self:framed() then
        frame:chrome(self)
    end
    for _, item in ipairs(self.items or {}) do
        item:draw(frame)
    end
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

return M
