local class = require("ito.class")
local host = require("ito.host")
local layout = require("ito.layout")
local Line = require("ito.line")
local text = require("ito.text")
local View = require("ito.view")

local M = {}

local SINGLE = "^" .. text.CHAR .. "$"

local function typed(chord)
    return not chord.ctrl and not chord.alt and type(chord.key) == "string" and chord.key:match(SINGLE) ~= nil
end

local function clamp(value, low, high)
    return math.max(math.min(value, high), low)
end

local EDITS = {
    left = "left",
    right = "right",
    home = "home",
    ["end"] = "tail",
    backspace = "backspace",
    delete = "delete_forward",
}

local TextField = class(View)
M.TextField = TextField

function TextField:init(value)
    View.init(self, {})
    if type(value) ~= "table" then
        error("TextField takes an ito.state that holds its text", 3)
    end
    self.value = value
end

function TextField:placeholder(hint)
    self.hint = hint
    return self
end

function TextField:hidden()
    self.masked = true
    return self
end

function TextField:on_submit(handler)
    self.submit = handler
    return self
end

function TextField:focused()
    self.wanted = true
    return self
end

function TextField:field()
    local memo, wanted = self.memo, self.value.value or ""
    memo.line = memo.line or Line(wanted)
    if memo.line.text ~= wanted then
        memo.line:set(wanted)
    end
    return memo.line
end

function TextField:content_height()
    return 1
end

function TextField:draw_content(frame)
    local ctx, line = frame.ctx, self:field()
    local spans = ctx:typed(
        { text = line.text, cursor = line.cursor, hidden = self.masked },
        { text = ctx.style.input, cursor = ctx.style.cursor }
    )
    if line.text == "" and self.hint then
        spans[#spans + 1] = { self.hint, ctx.style.dim }
    end
    frame:lines(self.inner, { spans })
    frame:focusable(self.memo, function(chord)
        return self:handle(chord)
    end, self.wanted)
end

function TextField:handle(chord)
    local line = self:field()
    if typed(chord) then
        line:insert(chord.key)
    elseif chord.key == "enter" and self.submit then
        self.submit(line.text)
        return true
    elseif EDITS[chord.key] then
        line[EDITS[chord.key]](line)
    else
        return false
    end
    self.value.value = line.text
    return true
end

local List = class(View)
M.List = List

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

function List:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    return self
end

function List:cursor()
    local count = #self.items
    local cursor = self.selected and self.selected.value or self.memo.cursor or 1
    return count == 0 and 0 or clamp(cursor, 1, count)
end

function List:move(cursor)
    cursor = clamp(cursor, 1, math.max(#self.items, 1))
    if self.selected then
        self.selected.value = cursor
    else
        self.memo.cursor = cursor
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
    local cursor = self:cursor()
    local offset = clamp(self.memo.offset or 1, 1, math.max(#self.items, 1))
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

local ScrollView = class(View)
M.ScrollView = ScrollView

function ScrollView:init(child)
    View.init(self, { child })
end

function ScrollView:follow_end()
    self.follow = true
    return self
end

function ScrollView:content_height(frame, width)
    local child = self.composed and self.composed[1]
    return child and child:measure(frame, width) or 0
end

function ScrollView:arrange(frame, inner)
    local child = self.composed[1]
    if not child then
        return
    end
    local memo = self.memo
    local total = child:measure(frame, inner.width)
    local most = math.max(total - inner.height, 0)
    local offset = memo.offset
    if offset == nil or (self.follow and memo.pinned ~= false) then
        offset = self.follow and most or 0
    end
    memo.offset, memo.most = clamp(offset, 0, most), most
    child:place(frame, layout.rect(inner.x, inner.y - memo.offset, inner.width, total))
end

function ScrollView:scroll(rows)
    local memo = self.memo
    memo.offset = clamp((memo.offset or 0) + rows, 0, memo.most or 0)
    memo.pinned = memo.offset >= (memo.most or 0)
end

function ScrollView:draw(frame)
    if self:framed() then
        frame:chrome(self)
    end
    frame:clipped(self.inner, function()
        for _, child in ipairs(self.composed or {}) do
            child:draw(frame)
        end
    end)
    frame:scrollable(self.inner, function(rows)
        self:scroll(rows)
    end)
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

local Spinner = class(View)
M.Spinner = Spinner

function Spinner:init()
    View.init(self, {})
end

function Spinner:content_height()
    return 1
end

function Spinner:content_width(frame)
    return frame.ctx:measure(frame.ctx.symbols.spinner[1] or "")
end

function Spinner:draw_content(frame)
    local ctx = frame.ctx
    local frames, interval = ctx.symbols.spinner, ctx.limits.spinner_interval
    if #frames == 0 then
        return
    end
    local shown = frames[math.floor(host.clock() / interval) % #frames + 1]
    frame:lines(self.inner, { { { shown, ctx.style.accent } } })
    frame:again(interval)
end

return M
