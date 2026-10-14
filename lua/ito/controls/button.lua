local class = require("ito.class")
local Text = require("ito.views.text")

local Button = class(Text)
Button.standalone = false

function Button:init(content, action)
    Text.init(self, content)
    assert(type(action) == "function", "Button takes an action function")
    self.action = action
    self:padding({ horizontal = 1 })
    self.click = function()
        self:activate()
    end
end

function Button:activate()
    if not self.is_disabled then
        self.action()
    end
end

function Button:draw_content(frame)
    Text.draw_content(self, frame)
    if frame.window and frame.window:is_focused(self.memo) then
        frame:put(self.inner.y, self.inner.x - 1, { { "›", frame.ctx.styles.accent } }, 1)
    end
    if not self.is_disabled then
        frame:focusable(self.memo, function(chord)
            if chord.key == "enter" or chord.key == " " then
                self:activate()
                return true
            end
            return false
        end, self.wanted, self)
    end
end

return Button
