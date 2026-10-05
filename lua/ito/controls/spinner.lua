local class = require("ito.class")
local host = require("ito.host")
local View = require("ito.view")

local Spinner = class(View)

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
    frame:lines(self.inner, { { { shown, ctx.styles.accent } } })
    frame:again(interval)
end

return Spinner
