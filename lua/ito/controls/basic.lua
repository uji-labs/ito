local class = require("ito.class")
local layout = require("ito.layout")
local text = require("ito.text")
local Text = require("ito.views.text")
local View = require("ito.view")

local function disabled(self, value)
    self.is_disabled = value ~= false
    return self
end

local function on_change(self, handler)
    assert(type(handler) == "function", "on_change takes a function")
    self.changed = handler
    return self
end

local function label(self, value)
    assert(type(value) == "string", "label takes a string")
    self.caption = value
    return self
end

local function number(value, name)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, name .. " must be a finite number")
    return value
end

local Button = class(Text)
Button.standalone = false
Button.disabled = disabled

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

local Checkbox = class(View)
Checkbox.disabled = disabled
Checkbox.on_change = on_change

function Checkbox:init(content, value)
    View.init(self, {})
    assert(type(content) == "string", "Checkbox takes a text label")
    assert(type(value) == "table" and type(value.value) == "boolean", "Checkbox takes a boolean state")
    self.content, self.value = content, value
    self.click = function()
        self:set(not self.value.value)
    end
end

function Checkbox:description(detail)
    assert(type(detail) == "string", "description takes a string")
    self.detail = detail
    return self
end

function Checkbox:set(value)
    if self.is_disabled then
        return
    end
    self.value.value = value == true
    if self.changed then
        self.changed(self.value.value)
    end
end

function Checkbox:rows(width, active, styles)
    local rows = {}
    local wrap_width = math.max(1, width - 6)
    for index, part in ipairs(text.wrap(self.content, wrap_width)) do
        local prefix = index == 1 and ((active and "› " or "  ") .. (self.value.value and "[x] " or "[ ] ")) or "      "
        rows[#rows + 1] = { { prefix .. part, self.is_disabled and styles.dim or styles.text } }
    end
    if self.detail then
        for _, part in ipairs(text.wrap(self.detail, wrap_width)) do
            rows[#rows + 1] = { { "      " .. part, styles.dim } }
        end
    end
    return rows
end

function Checkbox:content_height(frame, width)
    return #self:rows(width, false, frame.ctx.styles)
end

function Checkbox:draw_content(frame)
    local active = frame.window and frame.window:is_focused(self.memo)
    local rows = self:rows(self.inner.width, active, frame.ctx.styles)
    frame:lines(self.inner, rows)
    if not self.is_disabled then
        frame:focusable(self.memo, function(chord)
            if chord.key == "enter" or chord.key == " " then
                self:set(not self.value.value)
                return true
            end
            return false
        end, self.wanted, self)
    end
end

local Toggle = class(Checkbox)

local Slider = class(View)
Slider.disabled = disabled
Slider.on_change = on_change
Slider.label = label

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

local Progress = class(View)
Progress.label = label

function Progress:init(value)
    View.init(self, {})
    self.value = math.max(0, math.min(1, number(value, "Progress")))
end

function Progress:content_height()
    return self.caption and 2 or 1
end

function Progress:draw_content(frame)
    local inner, styles = self.inner, frame.ctx.styles
    local row = inner.y
    if self.caption then
        frame:lines(inner, { { { self.caption, styles.dim } } })
        row = row + 1
    end
    local width = math.max(0, inner.width)
    local filled = math.floor(width * self.value)
    frame:lines(layout.rect(inner.x, row, width, 1), {
        { { string.rep("━", filled), styles.accent }, { string.rep("─", width - filled), styles.dim } },
    })
end

return { Button = Button, Checkbox = Checkbox, Toggle = Toggle, Slider = Slider, Progress = Progress }
