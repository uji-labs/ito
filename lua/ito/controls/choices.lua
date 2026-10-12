local class = require("ito.class")
local layout = require("ito.layout")
local Line = require("ito.line")
local List = require("ito.controls.list")
local stack = require("ito.views.stack")
local Text = require("ito.views.text")
local text = require("ito.text")
local Theme = require("ito.runtime.environment").Theme
local typing = require("ito.typing")

local HStack, VStack = stack.HStack, stack.VStack

local HINT = 1

local OTHER = {}

local Choices = class(List)

local function ordinal(ctx, index, digits)
    local shown = string.format(ctx.text.ordered, index)
    return shown .. string.rep(" ", math.max(digits + 2 - text.width(shown), 0))
end

function Choices:init(items)
    if type(items) ~= "table" then
        error("Choices takes a list of choices, not a " .. type(items), 3)
    end
    local rows = {}
    for index, item in ipairs(items) do
        if type(item) ~= "table" or type(item.label) ~= "string" then
            error("Choices takes choices with a label, not " .. tostring(item), 3)
        end
        if item.description ~= nil and type(item.description) ~= "string" then
            error("Choices takes a description that is a string, not a " .. type(item.description), 3)
        end
        rows[index] = item
    end
    rows[#rows + 1] = OTHER
    List.init(self, rows, function(row, index, active)
        return self:choice(row, index, active)
    end)
    self.choose = function(item, index)
        if self.picked then
            self.picked(item, index)
        end
    end
end

function Choices:on_choose(handler)
    if type(handler) ~= "function" then
        error("on_choose takes a function that gets the choice", 2)
    end
    self.picked = handler
    return self
end

function Choices:on_other(handler)
    if type(handler) ~= "function" then
        error("on_other takes a function that gets the answer that was written", 2)
    end
    self.wrote = handler
    return self
end

function Choices:answer()
    local memo = self.memo
    memo.line = memo.line or Line("")
    return memo.line
end

function Choices:digits()
    return #tostring(#self.items)
end

function Choices:written(ctx, index, active)
    local styles = ctx.styles
    local line = self:answer()
    local content
    if active then
        content = ctx:typed({ text = line.text, cursor = line.cursor }, { text = styles.input, cursor = styles.cursor })
        if line.text == "" then
            content[#content + 1] = { ctx.text.other, styles.dim }
        end
    else
        content = { { line.text ~= "" and line.text or ctx.text.other, line.text ~= "" and styles.text or styles.dim } }
    end
    table.insert(content, 1, { ordinal(ctx, index, self:digits()), styles.dim })
    return content
end

function Choices:choice(item, index, active)
    local ctx = Theme.current
    local styles = ctx.styles
    local digits = self:digits()
    local pointer = Text(ctx.symbols.pointer):style(styles.highlight):invisible(not active)
    if item == OTHER then
        return HStack({ pointer, Text(self:written(ctx, index, active)) }):spacing(1)
    end
    local label = HStack({
        pointer,
        Text({ { ordinal(ctx, index, digits), styles.dim }, { item.label, active and styles.highlight or styles.text } }),
    }):spacing(1)
    if not item.description or item.description == "" then
        return label
    end
    return VStack({
        label,
        Text(item.description):style(styles.dim):wrap():padding({ leading = digits + 4 }),
    })
end

function Choices:write()
    local line = self:answer()
    if line.text:match("%S") and self.wrote then
        self.wrote(line.text)
    end
    return true
end

function Choices:writing()
    return self:cursor() == #self.items
end

function Choices:handle(chord)
    if self:writing() then
        if typing.typed(chord) then
            self:answer():insert(chord.key)
            return true
        end
        if typing.edit(self:answer(), chord.key) then
            return true
        end
        if chord.key == "enter" then
            return self:write()
        end
    end
    if chord.key == "tab" then
        self:move(self:cursor() + 1)
        return true
    elseif chord.key == "backtab" then
        self:move(self:cursor() - 1)
        return true
    end
    return List.handle(self, chord)
end

function Choices:content_height(frame, width)
    local total = HINT
    for index, item in ipairs(self.items) do
        local view = self.composition:place(self:choice(item, index, false), self.node, index, self.environment)
        total = total + (view and view:measure(frame, width) or 0)
    end
    return total
end

function Choices:arrange(frame, inner)
    List.arrange(self, frame, layout.rect(inner.x, inner.y, inner.width, math.max(inner.height - HINT, 0)))
end

function Choices:draw_content(frame)
    List.draw_content(self, frame)
    local ctx = frame.ctx
    local rows = { { { ctx.text.choices, ctx.styles.dim } } }
    frame:lines(layout.rect(self.inner.x, self.inner.y + self.inner.height - HINT, self.inner.width, HINT), rows)
end

return Choices
