local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local function overlap(a, b)
    if not a then
        return b
    end
    local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
    local right = math.min(a.x + a.width, b.x + b.width)
    local bottom = math.min(a.y + a.height, b.y + b.height)
    return layout.rect(x, y, right - x, bottom - y)
end

local Frame = class()

Frame.overlap = overlap

function Frame:init(screen, ctx)
    self.screen = screen
    self.ctx = ctx
    self.focusables = {}
    self.key_handlers = {}
    self.scrollables = {}
end

function Frame:put(row, col, line, width)
    local clip = self.clipping
    if clip and (row < clip.y or row >= clip.y + clip.height) then
        return
    end
    self.screen:line(row, col, line, width)
end

function Frame:clip(rect)
    local outer = self.clipping
    self.clipping = overlap(outer, rect)
    return outer
end

function Frame:unclip(outer)
    self.clipping = outer
end

function Frame:clipped(rect)
    return self.clipping and overlap(self.clipping, rect) or rect
end

function Frame:shows(rect)
    if rect.width <= 0 or rect.height <= 0 then
        return false
    end
    local clip = self.clipping
    if not clip then
        return true
    end
    return rect.x < clip.x + clip.width and clip.x < rect.x + rect.width and rect.y < clip.y + clip.height and clip.y < rect.y + rect.height
end

function Frame:focusable(target, handle, wanted, view)
    local rect = view and view:surface()
    if rect then
        local width, height = self.screen:size()
        rect = overlap(rect, layout.rect(0, 0, width, height))
        if self.clipping then
            rect = overlap(rect, self.clipping)
        end
        if rect.width <= 0 or rect.height <= 0 then
            return
        end
    end
    self.focusables[#self.focusables + 1] = {
        target = target,
        handle = handle,
        wanted = wanted,
        scope = self.scope,
        view = view,
        rect = rect,
    }
end

function Frame:scrollable(rect, target, state, priority)
    self.scrollables[#self.scrollables + 1] = { rect = rect, target = target, state = state, scope = self.scope, priority = priority or 0 }
end

function Frame:again(seconds)
    self.wake = math.min(self.wake or seconds, seconds)
end

function Frame:lines(rect, rows)
    for index = 1, math.min(#rows, rect.height) do
        self:put(rect.y + index - 1, rect.x, rows[index], rect.width)
    end
end

function Frame:clear(rect)
    local area = self:clipped(rect)
    if area.width > 0 and area.height > 0 then
        self.screen:fill(area)
    end
end

function Frame:fill(rect, style)
    local painted = self:clipped(rect)
    if painted.width > 0 and painted.height > 0 then
        self.screen:paint(painted, style)
    end
end

function Frame:clickable(rect, handler)
    for row = rect.y, rect.y + rect.height - 1 do
        self:put(row, rect.x, { on_click = handler }, rect.width)
    end
end

function Frame:chrome(view)
    local rect = view:surface()
    if rect.width <= 0 or rect.height <= 0 then
        return
    end
    local set = view.edge
    if not set then
        return
    end
    local style = view.border_style or self.ctx.styles.border
    local bottom = rect.y + rect.height - 1
    local across = view.edges == View.Edges.horizontal
    if across then
        local rule = string.rep(set.horizontal, rect.width)
        self:put(rect.y, rect.x, { { rule, style } }, rect.width)
        if bottom > rect.y then
            self:put(bottom, rect.x, { { rule, style } }, rect.width)
        end
    else
        local rule = string.rep(set.horizontal, math.max(rect.width - 2, 0))
        self:put(rect.y, rect.x, { { set.top_left .. rule .. set.top_right, style } }, rect.width)
        for row = rect.y + 1, bottom - 1 do
            self:put(row, rect.x, { { set.vertical, style } }, 1)
            self:put(row, rect.x + rect.width - 1, { { set.vertical, style } }, 1)
        end
        if bottom > rect.y then
            self:put(bottom, rect.x, { { set.bottom_left .. rule .. set.bottom_right, style } }, rect.width)
        end
    end
    if view.heading then
        local side = across and 0 or 1
        self:put(rect.y, rect.x + side, view.heading, rect.width - side * 2)
    end
end

return Frame
