local class = require("ito.class")
local layout = require("ito.layout")

local ScrollState = class()

function ScrollState:init(opts)
    opts = opts or {}
    self.following = opts.follow == true
    self.pending = 0
    self.offset = 0
    self.moved = 0
    self.jumps = 0
    self.page = 1
end

function ScrollState:scroll(rows)
    self.pending = self.pending + rows
end

function ScrollState:to_top()
    self.pending = 0
    self.following = false
    self.offset = 0
    self.topped = true
end

function ScrollState:to_end()
    self.pending = 0
    self.topped = nil
    self.following = true
end

function ScrollState:resolve(most)
    local offset = self.following and most or self.offset
    if self.topped then
        offset, self.topped = 0, nil
    end
    if self.pending ~= 0 then
        if self.pending < 0 then
            self.following = false
        end
        offset, self.pending = offset + self.pending, 0
    end
    self.offset = layout.clamp(offset, 0, math.max(most, 0))
    return self.offset
end

function ScrollState.is(value)
    return getmetatable(value) == ScrollState
end

return ScrollState
