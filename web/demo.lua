local ito = require("ito")

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
        highlight = ito.TextStyle({ foreground = COLORS.accent }),
        border = ito.TextStyle({ foreground = COLORS.muted }),
        input = ito.TextStyle({ foreground = COLORS.text }),
        cursor = ito.TextStyle({ foreground = COLORS.cursor }),
        selection = ito.TextStyle({ reverse = true }),
    },
    symbols = { spinner = { "-", "+" }, mask = "•", cursor = "█", pointer = "❯" },
    borders = { plain = PLAIN, rounded = ROUNDED },
    limits = { spinner_interval = 0.1 },
    text = {
        ordered = "%d.",
        other = "Type something.",
        choices = "Enter to select · Tab/Arrow keys to navigate · Esc to cancel",
    },
    options = {},
    views = {},
}

local screen, input = ito.open()
local window = ito.Window(screen, function() end)
local themes = ito.Themes({ default = THEME })
local value = ito.state("")
local submitted = ito.state("Nothing submitted yet.")
local clicks = ito.state(0)
local build = ito.body(function()
    local ctx = ito.theme()
    return ito.VStack({
        ito.Text("Ito, running on Canvas"):bold():foreground(ito.rgb(0xb8e1bd)),
        ito.Text("Lua components + Rust layout + WebAssembly"):style(ctx.styles.dim):wrap(),
        ito.TextField(value):placeholder("Type something..."):focused():on_submit(function(text)
            submitted.value = "You wrote: " .. text
        end),
        ito.Text(submitted.value):wrap(),
        ito.Text("Clicks: " .. clicks.value):on_tap(function()
            clicks.value = clicks.value + 1
        end),
        ito.HStack({ ito.Spinner():width(2), ito.Text("The browser drives animation."):style(ctx.styles.dim) }),
        ito.Text("Wide text: 日本語  ·  café"),
        ito.Text({ { "Visit Lua.org", ctx.styles.accent, link = "https://www.lua.org/" } }),
    }):spacing(1):padding(1)
end)

-- A browser app returns one nonblocking function. The host invokes it after
-- input/resize and again after the delay it returns, in seconds.
return function()
    while true do
        local event = input:poll()
        if not event then
            break
        end
        if event.type == "key" then
            window:key(event)
        elseif event.type == "paste" then
            for char in event.text:gmatch(ito.text.CHAR) do
                window:key({ key = char, ctrl = false, alt = false, shift = false })
            end
        elseif event.type == "mouse" then
            if event.kind == "down" and event.button == "left" then
                window:press(event.row, event.col)
            elseif event.kind == "drag" and event.button == "left" then
                window:drag(event.row, event.col)
            elseif event.kind == "up" and event.button == "left" then
                window:release(event)
            elseif event.kind == "scroll_up" or event.kind == "scroll_down" then
                window:wheel(event.row, event.col, event.kind == "scroll_up" and -3 or 3)
            end
        end
    end
    screen:clear()
    window:render(build(), themes:context())
    screen:flush()
    return window.wake
end
