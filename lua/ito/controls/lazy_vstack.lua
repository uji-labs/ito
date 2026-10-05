local class = require("ito.class")
local Group = require("ito.views.group")
local layout = require("ito.layout")
local runtime = require("ito.runtime")
local ScrollState = require("ito.controls.scroll_state")
local View = require("ito.view")

local Row = runtime.view(function(props)
    return props.row(props.item, props.index)
end)

local LazyVStack = class(View)

LazyVStack.live = true

function LazyVStack:init(items, row)
    View.init(self, {})
    if type(items) ~= "table" then
        error("LazyVStack takes a list of items first, not a " .. type(items), 3)
    end
    if type(row) ~= "function" then
        error("LazyVStack takes a function that makes a row second", 3)
    end
    self.items, self.row = items, row
end

function LazyVStack:item_id(identify)
    if type(identify) ~= "function" then
        error("item_id takes a function that gives an item's id", 2)
    end
    self.identify = identify
    return self
end

function LazyVStack:state(scroll)
    if not ScrollState.is(scroll) then
        error("state takes an ito.ScrollState", 2)
    end
    self.scroll = scroll
    return self
end

function LazyVStack:footer(element)
    self.foot = element
    return self
end

function LazyVStack:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    return self
end

function LazyVStack:scroller()
    if not self.scroll then
        self.memo.scroll = self.memo.scroll or ScrollState()
        self.scroll = self.memo.scroll
    end
    return self.scroll
end

function LazyVStack:id_at(index)
    if not self.identify then
        return index
    end
    local id = self.identify(self.items[index], index)
    if id == nil then
        error("item_id gave no id for item " .. index, 0)
    end
    return id
end

function LazyVStack:find(id, hint)
    if hint and self.items[hint] ~= nil and self:id_at(hint) == id then
        return hint
    end
    for index = #self.items, 1, -1 do
        if self:id_at(index) == id then
            return index
        end
    end
end

function LazyVStack:item(index)
    local found = self.built[index]
    if not found then
        local id = self:id_at(index)
        if self.seen[id] then
            error("two items in the stack have the id " .. tostring(id), 0)
        end
        self.seen[id] = true
        local element = Row({ row = self.row, item = self.items[index], index = index })
        element.key = id
        local view = self.composition:place(element, self.node, index, self.environment)
        found = { id = id, view = view, rows = {} }
        if Group.is(view) then
            found.group = view
            found.count = view:count()
            self.groups[#self.groups + 1] = view
        else
            found.count = view and 1 or 0
        end
        self.built[index] = found
    end
    return found
end

function LazyVStack:entry(frame, index, sub)
    local item = self:item(index)
    local found = item.rows[sub]
    if not found then
        local view = item.group and item.group:child(sub) or item.view
        found = { view = view, height = view and self:measured(frame, view) or 0 }
        item.rows[sub] = found
    end
    return found
end

function LazyVStack:measured(frame, view)
    local width = self.width
    local known = self.heights[view] or self.known[view]
    if not known or known.width ~= width or known.revision ~= view.revision then
        known = { width = width, revision = view.revision, height = view:measure(frame, width) }
    end
    self.heights[view] = known
    return known.height
end

function LazyVStack:start(width)
    self.built, self.groups, self.seen, self.width = {}, {}, {}, width
    self.known, self.heights = self.memo.heights or {}, {}
    self.memo.heights = self.heights
end

function LazyVStack:height(frame, index, sub)
    return self:entry(frame, index, sub).height
end

function LazyVStack:count(index)
    return self:item(index).count
end

function LazyVStack:previous(index, sub)
    if sub > 1 then
        return index, sub - 1
    end
    for at = index - 1, 1, -1 do
        local count = self:count(at)
        if count > 0 then
            return at, count
        end
    end
end

function LazyVStack:next(index, sub)
    if index >= 1 and index <= #self.items and sub < self:count(index) then
        return index, sub + 1
    end
    for at = index + 1, #self.items do
        if self:count(at) > 0 then
            return at, 1
        end
    end
end

function LazyVStack:first()
    return self:next(0, 0)
end

function LazyVStack:from_end(frame, room)
    local total = 0
    local index, sub = self:previous(#self.items + 1, 0)
    while index do
        total = total + self:height(frame, index, sub)
        if total >= room then
            return index, sub, total - room
        end
        local before_index, before_sub = self:previous(index, sub)
        if not before_index then
            return index, sub, 0
        end
        index, sub = before_index, before_sub
    end
    return nil, nil, 0
end

function LazyVStack:shifted(frame, index, sub, offset, rows)
    offset = offset + rows
    while offset < 0 do
        local before_index, before_sub = self:previous(index, sub)
        if not before_index then
            break
        end
        index, sub = before_index, before_sub
        offset = offset + self:height(frame, index, sub)
    end
    offset = math.max(offset, 0)
    while offset >= self:height(frame, index, sub) do
        local after_index, after_sub = self:next(index, sub)
        if not after_index then
            break
        end
        offset = offset - self:height(frame, index, sub)
        index, sub = after_index, after_sub
    end
    return index, sub, offset
end

function LazyVStack:below(frame, index, sub, offset, limit)
    local total = -offset
    while index and total < limit do
        total = total + self:height(frame, index, sub)
        index, sub = self:next(index, sub)
    end
    return math.max(total, 0)
end

function LazyVStack:distance(frame, from, to)
    local total, index, sub = to.offset - from.offset, from.index, from.sub
    local forward = from.index < to.index or (from.index == to.index and from.sub <= to.sub)
    if not forward then
        return -self:distance(frame, to, from)
    end
    while index and not (index == to.index and sub == to.sub) do
        total = total + self:height(frame, index, sub)
        index, sub = self:next(index, sub)
    end
    return total
end

function LazyVStack:position(frame, room, scroll)
    local top = scroll.top
    local previous = top and self:find(top.id, top.index)
    if previous then
        previous = { index = previous, sub = math.min(top.sub, math.max(self:count(previous), 1)), offset = top.offset }
        if self:count(previous.index) == 0 then
            previous = nil
        end
    end
    local index, sub, offset
    if scroll.topped then
        scroll.topped, scroll.following = nil, false
        index, sub = self:first()
        offset = 0
    elseif not scroll.following and previous then
        index, sub, offset = previous.index, previous.sub, previous.offset
    else
        scroll.following = true
        index, sub, offset = self:from_end(frame, room)
    end
    if not index then
        return nil
    end
    if scroll.pending < 0 then
        scroll.following = false
    end
    index, sub, offset = self:shifted(frame, index, sub, offset, scroll.pending)
    scroll.pending = 0
    if not scroll.following and self:below(frame, index, sub, offset, room + 1) <= room then
        scroll.following = true
        index, sub, offset = self:from_end(frame, room)
    end
    if previous then
        scroll.moved = scroll.moved + self:distance(frame, previous, { index = index, sub = sub, offset = offset })
    end
    return index, sub, offset
end

function LazyVStack:content_height(frame, width)
    self:start(width)
    local total = 0
    local index, sub = self:first()
    while index do
        total = total + self:height(frame, index, sub)
        index, sub = self:next(index, sub)
    end
    return total
end

function LazyVStack:arrange(frame, inner)
    local scroll = self:scroller()
    self:start(inner.width)
    local foot, foot_height = nil, 0
    if self.foot then
        foot = self.composition:place(self.foot, self.node, "footer", self.environment)
        foot_height = foot and math.min(foot:measure(frame, inner.width), inner.height) or 0
    end
    local room = inner.height - foot_height
    local start, sub, offset = self:position(frame, room, scroll)
    local start_sub = sub
    local placed, y, bottom = {}, inner.y - (offset or 0), inner.y + room
    local index = start
    while index and y < bottom do
        local entry = self:entry(frame, index, sub)
        if entry.view then
            entry.view:place(frame, layout.rect(inner.x, y, inner.width, entry.height))
            placed[#placed + 1] = entry.view
        end
        y = y + entry.height
        index, sub = self:next(index, sub)
    end
    local shown = layout.clamp(y - inner.y, 0, room)
    if foot then
        foot:place(frame, layout.rect(inner.x, inner.y + shown, inner.width, foot_height))
    end
    self.placed, self.foot_view = placed, foot
    self.content = layout.rect(inner.x, inner.y, inner.width, room)
    if start then
        local item = self.built[start]
        scroll.top = { id = item.id, index = start, sub = start_sub, offset = offset }
    end
    scroll.viewport = { top = inner.y, height = shown, first = scroll.moved, width = inner.width }
    scroll.page = room
    for _, group in ipairs(self.groups) do
        group:finish()
    end
    self.node:sweep(self.composition.generation)
end

function LazyVStack:paint(frame)
    if self.fill then
        frame:fill(self.rect, self.fill)
    end
    if self:framed() then
        frame:chrome(self)
    end
    frame:clipped(self.content, function()
        for _, view in ipairs(self.placed or {}) do
            view:draw(frame)
        end
    end)
    if self.foot_view then
        self.foot_view:draw(frame)
    end
    local scroll = self:scroller()
    frame:scrollable(self.content, function(rows)
        scroll:scroll(rows)
    end, scroll)
    self:draw_extras(frame)
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

return LazyVStack
