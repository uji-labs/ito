local class = require("ito.class")
local layout = require("ito.layout")
local ScrollState = require("ito.controls.scroll_state")
local View = require("ito.view")

local ScrollView = class(View)

ScrollView.live = true

function ScrollView:init(child)
    View.init(self, { child })
end

function ScrollView:follow_end()
    self.follow = true
    return self
end

function ScrollView:state(scroll)
    if not ScrollState.is(scroll) then
        error("state takes an ito.ScrollState", 2)
    end
    self.position = scroll
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
    if self.position then
        self.position.page = inner.height
        memo.offset, memo.most = self.position:resolve(most), most
        child:place(frame, layout.rect(inner.x, inner.y - memo.offset, inner.width, total))
        return
    end
    local offset = memo.offset
    if offset == nil or (self.follow and memo.pinned ~= false) then
        offset = self.follow and most or 0
    end
    memo.offset, memo.most = layout.clamp(offset, 0, most), most
    child:place(frame, layout.rect(inner.x, inner.y - memo.offset, inner.width, total))
end

function ScrollView:scroll(rows)
    if self.position then
        self.position:scroll(rows)
        return
    end
    local memo = self.memo
    memo.offset = layout.clamp((memo.offset or 0) + rows, 0, memo.most or 0)
    memo.pinned = memo.offset >= (memo.most or 0)
end

function ScrollView:paint(frame)
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
    end, self.position)
    self:draw_extras(frame)
    if self.click then
        frame:clickable(self.rect, self.click)
    end
end

return ScrollView
