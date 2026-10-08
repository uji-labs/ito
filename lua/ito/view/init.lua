local class = require("ito.class")
local layout = require("ito.layout")
local runtime = require("ito.runtime")
local scope = require("ito.runtime.scope")

local View = class(runtime.Primitive)

View.Edges = { all = {}, horizontal = {} }
View.Alignment = require("ito.view.alignment").Alignment
View.alignment_of = require("ito.view.alignment").of

require("ito.view.modifiers")(View)

local function measured_inset(view)
    local top, bottom = view.pad_top or 0, view.pad_bottom or 0
    local left, right = view.pad_leading or 0, view.pad_trailing or 0
    if view.edge then
        top, bottom = top + 1, bottom + 1
        if view.edges ~= View.Edges.horizontal then
            left, right = left + 1, right + 1
        end
    end
    local outer_top, outer_bottom = view.margin_top or 0, view.margin_bottom or 0
    local outer_left, outer_right = view.margin_leading or 0, view.margin_trailing or 0
    local outer = outer_top + outer_bottom + outer_left + outer_right
    return {
        top + outer_top,
        bottom + outer_bottom,
        left + outer_left,
        right + outer_right,
        top + bottom + left + right + outer > 0 or view.edge ~= nil,
        outer > 0 and { outer_top, outer_bottom, outer_left, outer_right } or nil,
    }
end

function View:chrome()
    local inset = self.inset
    if not inset then
        inset = measured_inset(self)
        self.inset = inset
    end
    return inset[1], inset[2], inset[3], inset[4]
end

function View:surface()
    if not self.inset then
        self:chrome()
    end
    local outer, rect = self.inset[6], self.rect
    if not outer then
        return rect
    end
    return layout.rect(
        rect.x + outer[3],
        rect.y + outer[1],
        math.max(rect.width - outer[3] - outer[4], 0),
        math.max(rect.height - outer[1] - outer[2], 0)
    )
end

function View:framed()
    if not self.inset then
        self:chrome()
    end
    return self.inset[5]
end

function View:content_height()
    return 0
end

function View:content_width()
    return nil
end

function View:measure(frame, width)
    if self.is_hidden then
        return 0
    end
    if self.fixed_height then
        return self.fixed_height
    end
    local top, bottom, left, right = self:chrome()
    local rows = self:content_height(frame, math.max(width - left - right, 0))
    if rows == 0 and self:framed() then
        return 0
    end
    return math.min(rows + top + bottom, self.most_height or math.huge)
end

function View:natural_width(frame)
    if self.is_hidden then
        return 0
    end
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
    if self.is_hidden then
        return 0
    end
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

function View.fit(frame, child, area, alignment)
    local width = child.fixed_width or (not child.weight and child:natural_width(frame)) or area.width
    width = math.min(width, area.width)
    local height
    if child.fixed_height then
        height = child.fixed_height
    elseif child.weight then
        height = area.height
    else
        height = child:measure(frame, width)
    end
    height = math.min(height, area.height)
    local at = child.aligned or alignment
    local x = area.x + math.floor((area.width - width) * at.x)
    local y = area.y + math.floor((area.height - height) * at.y)
    return layout.rect(x, y, width, height)
end

function View:attach(composition, node, environment)
    local extras = {}
    for index, entry in ipairs(self.overlays or {}) do
        extras[#extras + 1] = {
            view = composition:place(entry.content, node, "overlay " .. index, environment),
            alignment = entry.alignment,
        }
    end
    for index, entry in ipairs(self.readers or {}) do
        local value = runtime.merged(self, entry.key)
        extras[#extras + 1] = {
            view = composition:place(runtime.Build({ build = entry.build, value = value }), node, "reader " .. index, environment),
            alignment = entry.alignment,
        }
    end
    self.extras = extras
end

local function steady(views)
    for _, view in ipairs(views or {}) do
        if not view:steady() then
            return false
        end
    end
    return true
end

function View:steady()
    local known = self.settled
    if known == nil then
        known = not self.live and steady(self.composed)
        for _, extra in ipairs(self.extras or {}) do
            known = known and (not extra.view or extra.view:steady())
        end
        self.settled = known
    end
    return known
end

function View:place(frame, rect)
    local last = self.rect
    if last and last.x == rect.x and last.y == rect.y and last.width == rect.width and last.height == rect.height and self:steady() then
        return
    end
    self.rect = rect
    if self.is_hidden then
        self.inner = rect
        return
    end
    local top, bottom, left, right = self:chrome()
    self.inner = layout.rect(rect.x + left, rect.y + top, rect.width - left - right, rect.height - top - bottom)
    self:arrange(frame, self.inner)
    for _, extra in ipairs(self.extras or {}) do
        if extra.view then
            extra.view:place(frame, View.fit(frame, extra.view, rect, extra.alignment))
        end
    end
end

function View:arrange(frame, inner)
    for _, child in ipairs(self.composed or {}) do
        child:place(frame, inner)
    end
end

function View:draw_content() end

function View:draw(frame)
    if self.is_hidden or self.is_invisible then
        return
    end
    local outer = frame.scope
    if self.scoped ~= nil then
        frame.scope = self.scoped
    end
    if self.opaque_fill then
        frame:clear(self.rect)
    end
    self:paint(frame)
    frame.scope = outer
end

function View:paint(frame)
    if self.fill then
        frame:fill(self:surface(), self.fill)
    end
    if self:framed() then
        frame:chrome(self)
    end
    self:draw_content(frame)
    for _, child in ipairs(self.composed or {}) do
        if not child.rect or frame:shows(child.rect) then
            child:draw(frame)
        end
    end
    self:draw_extras(frame)
    if self.click then
        frame:clickable(self:surface(), self.click)
    end
end

function View:draw_extras(frame)
    for _, extra in ipairs(self.extras or {}) do
        if extra.view then
            extra.view:draw(frame)
        end
    end
end

scope.modifiers = View

return View
