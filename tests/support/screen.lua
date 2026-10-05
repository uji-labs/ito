local ito = require("ito")
local tty = require("ito.tty")

local M = {}

local SCROLL = 3

local PLAIN = { top_left = "┌", top_right = "┐", bottom_left = "└", bottom_right = "┘", horizontal = "─", vertical = "│" }
local ROUNDED = { top_left = "╭", top_right = "╮", bottom_left = "╰", bottom_right = "╯", horizontal = "─", vertical = "│" }

local COLORS = {
    text = ito.rgb(0xd4d4d4),
    muted = ito.rgb(0x808080),
    accent = ito.Color.cyan,
    cursor = ito.Color.white,
}

local THEME = {
    name = "test",
    colors = COLORS,
    styles = {
        text = ito.TextStyle({ foreground = COLORS.text }),
        dim = ito.TextStyle({ foreground = COLORS.muted, dim = true }),
        accent = ito.TextStyle({ foreground = COLORS.accent, bold = true }),
        border = ito.TextStyle({ foreground = COLORS.muted }),
        input = ito.TextStyle({ foreground = COLORS.text }),
        cursor = ito.TextStyle({ foreground = COLORS.cursor }),
        selection = ito.TextStyle({ reverse = true }),
    },
    symbols = { spinner = { "-", "+" }, mask = "•", cursor = "█" },
    borders = { plain = PLAIN, rounded = ROUNDED },
    limits = { spinner_interval = 0.1 },
    text = {},
    options = {},
    views = {},
}

M.THEME = THEME

local Screen = {}
Screen.__index = Screen

local function blank()
    return { key = "", ctrl = false, alt = false, shift = false }
end

function Screen:show(build)
    self.build = ito.body(function()
        return build(ito.theme())
    end)
    return self:rows()
end

function Screen:render()
    self.screen:clear()
    self.frame = self.window:render(self.build(), self.themes:context())
    self.focused = self.window.focused
end

function Screen:rows()
    self:render()
    local rows = {}
    for row = 0, self.height - 1 do
        rows[#rows + 1] = self.screen:text(row)
    end
    return rows
end

function Screen:press(...)
    for _, key in ipairs({ ... }) do
        local chord = blank()
        chord.key = key
        if self.focused then
            self.focused(chord)
        end
        self:render()
    end
    return self:rows()
end

function Screen:tap(row, col)
    local handler = self.screen:clicked(row, col)
    if handler then
        handler()
    end
    return self:rows()
end

function Screen:wheel(row, col, direction)
    self.window:wheel(row, col, direction * SCROLL)
    return self:rows()
end

function M.new(width, height)
    local screen = tty.virtual(width, height)
    local self = setmetatable({
        screen = screen,
        width = width,
        height = height,
        themes = ito.Themes({
            default = THEME,
            load = function(name)
                error("no theme named " .. name, 0)
            end,
        }),
    }, Screen)
    self.window = ito.Window(screen, function() end)
    return self
end

function M.trimmed(row)
    return (row:gsub("%s+$", ""))
end

return M
