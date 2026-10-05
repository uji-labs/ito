local class = require("ito.class")
local View = require("ito.view")

local ZStack = class(View)

function ZStack:init(props)
    View.init(self, props)
    self.layered = View.alignment_of((props or {}).alignment, "ZStack")
end

function ZStack:content_height(frame, width)
    local most = 0
    for _, child in ipairs(self.composed or {}) do
        most = math.max(most, child.fixed_height or child:measure(frame, width))
    end
    return most
end

function ZStack:content_width(frame)
    local most
    for _, child in ipairs(self.composed or {}) do
        local used = child.fixed_width or child:natural_width(frame)
        if not used then
            return nil
        end
        most = math.max(most or 0, used)
    end
    return most
end

function ZStack:arrange(frame, inner)
    for _, child in ipairs(self.composed or {}) do
        child:place(frame, View.fit(frame, child, inner, self.layered))
    end
end

return ZStack
