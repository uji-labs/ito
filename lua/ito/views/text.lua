local class = require("ito.class")
local color = require("ito.style.color")
local spans = require("ito.spans")
local text = require("ito.text")
local text_style = require("ito.style.text_style")
local View = require("ito.view")

local TextStyle = text_style.TextStyle

local Text = class(View)

function Text:init(content)
    View.init(self, {})
    if type(content) ~= "string" and type(content) ~= "table" then
        error("Text takes a string or a list of spans, not a " .. type(content), 3)
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

function Text:wrap()
    self.wrapping = true
    return self
end

function Text:repeating()
    self.repeats = true
    return self
end

local function split(content, style)
    if type(content) == "string" then
        local out = {}
        for index, line in ipairs(text.lines(content)) do
            out[index] = { { line, style } }
        end
        return out
    end
    local plain = style == text_style.plain
    local out, line = {}, {}
    for _, span in ipairs(content) do
        local kept = span[2] and (plain and span[2] or style:merge(span[2])) or style
        local value = span[1]
        if not value:find("\n", 1, true) then
            if value ~= "" then
                line[#line + 1] = { value, kept }
            end
        else
            local first = true
            for part in (value .. "\n"):gmatch("([^\n]*)\n") do
                if not first then
                    out[#out + 1], line = line, {}
                end
                first = false
                part = part:gsub("\r$", "")
                if part ~= "" then
                    line[#line + 1] = { part, kept }
                end
            end
        end
    end
    out[#out + 1] = line
    return out
end

function Text:lines()
    local style = self.text_style
    if self.lines_style ~= style then
        self.lines_style, self.made_lines = style, split(self.content, style)
        self.rows_width = nil
    end
    return self.made_lines
end

function Text:rows(width)
    local lines = self:lines()
    if not self.wrapping then
        return lines
    end
    if self.rows_width ~= width then
        local rows = {}
        for _, line in ipairs(lines) do
            for _, row in ipairs(spans.wrap(line, width)) do
                rows[#rows + 1] = row
            end
        end
        self.rows_width, self.made_rows = width, rows
    end
    return self.made_rows
end

function Text:content_height(_, width)
    return #self:rows(width)
end

function Text:content_width()
    return text.widest(self:lines())
end

local function tiled(row, width)
    local used = text.widest({ row })
    if used == 0 or used >= width then
        return row
    end
    local out = {}
    for _ = 1, math.ceil(width / used) do
        for _, span in ipairs(row) do
            out[#out + 1] = span
        end
    end
    return out
end

function Text:draw_content(frame)
    local inner = self.inner
    local rows = self:rows(inner.width)
    if self.repeats and #rows > 0 then
        local filled = {}
        for index = 1, inner.height do
            filled[index] = tiled(rows[(index - 1) % #rows + 1], inner.width)
        end
        rows = filled
    end
    frame:lines(inner, rows)
end

return Text
