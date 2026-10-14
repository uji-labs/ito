local class = require("ito.class")
local View = require("ito.view")

local function number(value, name)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, name .. " must be a finite number")
    return value
end

local Slider = class(View)

function Slider:init(value, opts)
    View.init(self, {})
    assert(type(value) == "table", "Slider takes a number state")
    number(value.value, "Slider state")
    opts = opts or {}
    self.value = value
    self.minimum = number(opts.min or 0, "Slider min")
    self.maximum = number(opts.max or 100, "Slider max")
    self.step = number(opts.step or 1, "Slider step")
    assert(self.maximum > self.minimum and self.step > 0, "Slider needs max above min and a positive step")
end

function Slider:suffix(unit)
    assert(type(unit) == "string", "suffix takes a string")
    self.unit = unit
    return self
end

function Slider:set(value)
    if self.is_disabled then
        return
    end
    value = number(value, "Slider value")
    local steps = math.floor((value - self.minimum) / self.step + 0.5)
    self.value.value = math.max(self.minimum, math.min(self.maximum, self.minimum + steps * self.step))
    if self.changed then
        self.changed(self.value.value)
    end
end

function Slider:content_height()
    return 1
end

function Slider:draw_content(frame)
    local prefix = (frame.window and frame.window:is_focused(self.memo) and "› " or "  ") .. (self.caption and self.caption .. ": " or "")
    frame:lines(self.inner, { { { prefix .. tostring(self.value.value) .. (self.unit or "") .. "  < >", frame.ctx.styles.text } } })
    if not self.is_disabled then
        frame:focusable(self.memo, function(chord)
            if chord.key == "left" or chord.key == "down" then
                self:set(self.value.value - self.step)
            elseif chord.key == "right" or chord.key == "up" then
                self:set(self.value.value + self.step)
            elseif chord.key == "home" then
                self:set(self.minimum)
            elseif chord.key == "end" then
                self:set(self.maximum)
            else
                return false
            end
            return true
        end, self.wanted, self)
    end
end

return Slider
