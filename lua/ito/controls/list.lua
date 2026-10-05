local class = require("ito.class")
local layout = require("ito.layout")
local View = require("ito.view")

local List = class(View)

function List:init(items, row)
    View.init(self, {})
    if type(items) ~= "table" then
        error("List takes a list of items first, not a " .. type(items), 3)
    end
    if type(row) ~= "function" then
        error("List takes a function that makes a row second", 3)
    end
    self.items, self.row = items, row
end

function List:selection(state)
    self.selected = state
    return self
end

function List:on_choose(handler)
    self.choose = handler
    return self
end

function List:focused()
    self.wanted = true
    return self
end

function List:passive()
    self.inert = true
    return self
end

function List:footer(builder)
    self.foot = builder
    return self
end

function List:item_id(identify)
    if type(identify) ~= "function" then
        error("item_id takes a function that gives an item's id", 2)
    end
    self.identify = identify
    return self
end

function List:identities()
    if not self.identify then
        return nil, nil
    end
    local ids, at = {}, {}
    for index, item in ipairs(self.items) do
        local id = self.identify(item, index)
        if id == nil then
            error("item_id gave no id for item " .. index, 0)
        end
        if at[id] then
            error("two items in the list have the id " .. tostring(id), 0)
        end
        ids[index], at[id] = id, index
    end
    return ids, at
end

function List:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    return self
end

function List:cursor()
    local count = #self.items
    local chosen = not self.selected and self.at and self.at[self.memo.chosen]
    local cursor = chosen or self.selected and self.selected.value or self.memo.cursor or 1
    return count == 0 and 0 or layout.clamp(cursor, 1, count)
end

function List:move(cursor)
    cursor = layout.clamp(cursor, 1, math.max(#self.items, 1))
    if self.selected then
        self.selected.value = cursor
    else
        self.memo.cursor = cursor
        self.memo.chosen = self.ids and self.ids[cursor]
    end
end

function List:content_height()
    return #self.items
end

function List:footing(frame, first, last, inner)
    local element = self.foot(first, last, #self.items)
    local view = element and self.composition:place(element, self.node, "footer", self.environment)
    return view, view and view:measure(frame, inner.width) or 0
end

function List:rows(frame, offset, inner)
    local placed, used, index = {}, 0, offset
    local cursor = self:cursor()
    while index <= #self.items and used < inner.height do
        local element = self.row(self.items[index], index, index == cursor)
        if element and self.ids then
            element.key = self.ids[index]
        end
        local view = self.composition:place(element, self.node, index, self.environment)
        local height = view and view:measure(frame, inner.width) or 0
        placed[#placed + 1] = { view = view, height = height, index = index }
        used, index = used + height, index + 1
    end
    return placed, used
end

function List:arrange(frame, inner)
    local room = inner
    local reserved = 0
    if self.foot then
        local _, height = self:footing(frame, 1, 1, inner)
        reserved = math.min(height, inner.height)
        room = layout.rect(inner.x, inner.y, inner.width, inner.height - reserved)
    end
    inner = room
    self.ids, self.at = self:identities()
    local cursor = self:cursor()
    if self.ids and not self.selected then
        self.memo.chosen = self.ids[cursor]
    end
    local first = self.at and self.at[self.memo.first]
    local offset = layout.clamp(first or self.memo.offset or 1, 1, math.max(#self.items, 1))
    if cursor > 0 and cursor < offset then
        offset = cursor
    end
    local placed, used = self:rows(frame, offset, inner)
    while cursor > 0 and offset < cursor do
        local last = placed[#placed]
        if last and (cursor < last.index or (cursor == last.index and used <= inner.height)) then
            break
        end
        offset = offset + 1
        placed, used = self:rows(frame, offset, inner)
    end
    self.memo.offset, self.memo.visible = offset, #placed
    self.memo.first = self.ids and self.ids[offset]
    local y = inner.y
    for _, row in ipairs(placed) do
        if row.view then
            row.view:place(frame, layout.rect(inner.x, y, inner.width, row.height))
        end
        y = y + row.height
    end
    self.placed = placed
    self.footing_view = nil
    if reserved > 0 and #placed > 0 then
        local view = self:footing(frame, placed[1].index, placed[#placed].index, inner)
        if view then
            view:place(frame, layout.rect(inner.x, inner.y + inner.height, inner.width, reserved))
            self.footing_view = view
        end
    end
    self.node:sweep(self.composition.generation)
end

function List:draw_content(frame)
    frame:clipped(self.inner, function()
        for _, row in ipairs(self.placed or {}) do
            if row.view then
                row.view:draw(frame)
            end
        end
        if self.footing_view then
            self.footing_view:draw(frame)
        end
    end)
    if not self.inert then
        frame:focusable(self.memo, function(chord)
            return self:handle(chord)
        end, self.wanted)
    end
    frame:scrollable(self.inner, function(rows)
        self:move(self:cursor() + rows)
    end)
end

function List:handle(chord)
    local key, cursor = chord.key, self:cursor()
    local page = math.max(self.memo.visible or 1, 1)
    if key == "up" then
        self:move(cursor - 1)
    elseif key == "down" then
        self:move(cursor + 1)
    elseif key == "pageup" then
        self:move(cursor - page)
    elseif key == "pagedown" then
        self:move(cursor + page)
    elseif key == "home" then
        self:move(1)
    elseif key == "end" then
        self:move(#self.items)
    elseif key == "enter" and self.choose and cursor > 0 then
        self.choose(self.items[cursor], cursor)
    else
        return false
    end
    return true
end

return List
