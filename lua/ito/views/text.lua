local class = require("ito.class")
local color = require("ito.style.color")
local text = require("ito.text")
local text_style = require("ito.style.text_style")
local View = require("ito.view")

local TextStyle = text_style.TextStyle

local Text = class(View)

function Text:init(content)
    View.init(self, {})
    if type(content) ~= "string" then
        error("Text takes a string, not a " .. type(content), 3)
    end
    self.content = content
    self.text_style = text_style.plain
end

for _, flag in ipairs(text_style.FLAGS) do
    local only = TextStyle({ [flag] = true })
    Text[flag] = function(self)
        self.text_style = self.text_style:merge(only)
        return self
    end
end

function Text:foreground(value)
    self.text_style = self.text_style:merge(TextStyle({ foreground = color.check(value, "foreground") }))
    return self
end

function Text:style(value)
    self.text_style = self.text_style:merge(text_style.check(value, "style"))
    return self
end

function Text:rows()
    local style = self.text_style
    local rows = {}
    for index, line in ipairs(text.lines(self.content)) do
        rows[index] = { { line, style } }
    end
    return rows
end

function Text:content_height()
    return #text.lines(self.content)
end

function Text:content_width()
    return text.widest(self:rows())
end

function Text:draw_content(frame)
    frame:lines(self.inner, self:rows())
end

return Text
