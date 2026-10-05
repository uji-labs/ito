local class = require("ito.class")
local layout = require("ito.layout")
local runtime = require("ito.runtime")
local schema = require("ito.theme.schema")

local View = class(runtime.Primitive)

local EDGES = { "top_left", "top_right", "bottom_left", "bottom_right", "horizontal", "vertical" }

View.Edges = { all = {}, horizontal = {} }
View.Side = { top = "top", bottom = "bottom", left = "left", right = "right" }

local SIDES = {}
for _, side in pairs(View.Side) do
    SIDES[side] = true
end

local function whole(value, what)
    if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
        error(what .. " must be a whole number of cells, not " .. tostring(value), 3)
    end
    return value
end

local FULL = 100
local SHARE = "^%s*(%d+)%s*%%%s*$"
local FLOATING = { percent = 80 }

local function extent(value, what)
    if value == nil then
        return FLOATING
    end
    if type(value) == "number" then
        return { cells = whole(value, what) }
    end
    local percent = type(value) == "string" and tonumber(value:match(SHARE))
    if not percent or percent < 1 or percent > FULL then
        error(what .. ' takes a number of cells or a share such as "80%", not ' .. tostring(value), 3)
    end
    return { percent = percent }
end

function View:padding(amount)
    if type(amount) == "table" then
        self.pad_y = whole(amount.vertical or 0, "vertical padding")
        self.pad_x = whole(amount.horizontal or 0, "horizontal padding")
    else
        local cells = whole(amount, "padding")
        self.pad_x, self.pad_y = cells, cells
    end
    return self
end

function View:border(set, opts)
    if type(set) ~= "table" then
        error("a border needs one of the theme's borders, not " .. tostring(set), 2)
    end
    for _, edge in ipairs(EDGES) do
        if type(set[edge]) ~= "string" then
            error("a border needs " .. edge, 2)
        end
    end
    opts = opts or {}
    local edges = opts.edges or View.Edges.all
    if edges ~= View.Edges.all and edges ~= View.Edges.horizontal then
        error("a border's edges are Edges.all or Edges.horizontal", 2)
    end
    self.edge, self.edges = set, edges
    self.border_color = opts.color ~= nil and schema.color(opts.color) or nil
    return self
end

function View:background(color)
    self.fill = schema.color(color)
    return self
end

function View:title(title)
    self.heading = title
    return self
end

function View:grow(weight)
    weight = weight or 1
    if type(weight) ~= "number" or weight <= 0 then
        error("grow takes a weight above 0, not " .. tostring(weight), 2)
    end
    self.weight = weight
    return self
end

function View:height(cells)
    self.fixed_height = whole(cells, "height")
    return self
end

function View:width(cells)
    self.fixed_width = whole(cells, "width")
    return self
end

function View:share(fraction)
    if type(fraction) ~= "number" or fraction < 0 or fraction > 1 then
        error("share takes a fraction from 0 to 1, not " .. tostring(fraction), 2)
    end
    self.fraction = fraction
    return self
end

function View:dock(side)
    if not SIDES[side] then
        error("dock takes Side.top, Side.bottom, Side.left or Side.right", 2)
    end
    self.side = side
    return self
end

function View:float(size)
    size = size or {}
    if type(size) ~= "table" then
        error("float takes a table with width and height", 2)
    end
    self.floating = { width = extent(size.width, "float width"), height = extent(size.height, "float height") }
    return self
end

function View:id(key)
    self.key = key
    return self
end

function View:on_tap(handler)
    if type(handler) ~= "function" then
        error("on_tap takes a function", 2)
    end
    self.click = handler
    return self
end

function View:chrome()
    local top, left = self.pad_y or 0, self.pad_x or 0
    local bottom, right = top, left
    if self.edge then
        top, bottom = top + 1, bottom + 1
        if self.edges ~= View.Edges.horizontal then
            left, right = left + 1, right + 1
        end
    end
    return top, bottom, left, right
end

function View:framed()
    return self.edge ~= nil or (self.pad_x or 0) > 0 or (self.pad_y or 0) > 0
end

function View:content_height()
    return 0
end

function View:content_width()
    return nil
end

function View:measure(frame, width)
    if self.fixed_height then
        return self.fixed_height
    end
    local top, bottom, left, right = self:chrome()
    local rows = self:content_height(frame, math.max(width - left - right, 0))
    if rows == 0 and self:framed() then
        return 0
    end
    return rows + top + bottom
end

function View:natural_width(frame)
    if self.fixed_width then
        return self.fixed_width
    end
    local content = self:content_width(frame)
    if not content then
        return nil
    end
    local _, _, left, right = self:chrome()
    return content + left + right
end

function View:extent(frame, rect, down)
    local total = down and rect.height or rect.width
    local fixed = down and self.fixed_height or self.fixed_width
    if fixed then
        return fixed
    elseif self.fraction then
        return math.floor(total * self.fraction)
    elseif self.weight then
        return { weight = self.weight }
    elseif down then
        return self:measure(frame, rect.width)
    end
    return self:natural_width(frame) or { weight = 1 }
end

function View:place(frame, rect)
    self.rect = rect
    local top, bottom, left, right = self:chrome()
    self.inner = layout.rect(rect.x + left, rect.y + top, rect.width - left - right, rect.height - top - bottom)
    self:arrange(frame, self.inner)
end

function View:arrange(frame, inner)
    for _, child in ipairs(self.composed or {}) do
        child:place(frame, inner)
    end
end

function View:draw_content() end

function View:draw(frame)
    if self.fill then
        frame:fill(self.rect, self.fill)
    end
    if self:framed() then
        frame:chrome(self)
    end
    self:draw_content(frame)
    for _, child in ipairs(self.composed or {}) do
        child:draw(frame)
    end
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

runtime.modifiers = View

return View
