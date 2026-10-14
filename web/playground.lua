-- A small terminal host. All drawing, focus, and input still run through Ito.
local ito = require("ito")

return function(draw, palette)
    local function color(name, fallback)
        local value = palette[name]
        local hex = type(value) == "string" and value:match("^#(%x%x%x%x%x%x)$")
        return ito.rgb(hex and tonumber(hex, 16) or fallback)
    end
    local ink, paper = color("foreground", 0x26372e), color("background", 0xfffdf7)
    local muted, accent = color("muted", 0x6f7768), color("accent", 0xc65036)
    local rule = color("rule", 0xb8bbab)
    local themes = ito.Themes({
        default = {
            name = "browser",
            colors = { text = ink, muted = muted, accent = accent, cursor = ink },
            styles = {
                text = ito.TextStyle({ foreground = ink }),
                dim = ito.TextStyle({ foreground = muted }),
                accent = ito.TextStyle({ foreground = accent, bold = true }),
                highlight = ito.TextStyle({ foreground = ink, bold = true, underline = true }),
                border = ito.TextStyle({ foreground = rule }),
                input = ito.TextStyle({ foreground = ink }),
                cursor = ito.TextStyle({ foreground = paper, background = ink }),
                selection = ito.TextStyle({ reverse = true }),
            },
            symbols = { spinner = { "-", "+" }, mask = "•", cursor = "▏", pointer = "›" },
            borders = {
                plain = {
                    top_left = "┌",
                    top_right = "┐",
                    bottom_left = "└",
                    bottom_right = "┘",
                    horizontal = "─",
                    vertical = "│",
                },
                rounded = {
                    top_left = "╭",
                    top_right = "╮",
                    bottom_left = "╰",
                    bottom_right = "╯",
                    horizontal = "─",
                    vertical = "│",
                },
            },
            text = { ordered = "%d.", other = "Type something.", choices = "Enter to select · Esc to cancel" },
            limits = { spinner_interval = 0.1 },
            options = {},
            views = {},
        },
    })
    local screen, input = ito.open()
    local window = ito.Window(screen, function() end)
    window.active = false
    local build = ito.body(draw)
    local info = {}

    local function render()
        screen:clear()
        local root, frame = window:place(ito.VStack({ build() }), themes:context())
        local width, height = screen:size()
        -- A page whose only child grows fills the screen; every other page is
        -- as tall as the content it drew.
        local content = root.composed and root.composed[1]
        local wanted = content and (content.weight or content.fraction) and height or root:measure(frame, width)
        info.height = math.max(1, math.min(height, wanted))
        window:draw(root, frame)
        screen:flush()
        info.targets, info.focus, info.scrollables = {}, nil, {}
        for _, entry in ipairs(window.scrollables) do
            info.scrollables[#info.scrollables + 1] = entry.rect
        end
        for index, entry in ipairs(window.focusables) do
            local view, rect = entry.view, entry.rect
            if view and rect then
                local target = {
                    rect = rect,
                    index = index,
                    count = #window.focusables,
                    text_input = view.text_input == true or (view.writing and view:writing()) or false,
                    label = view.accessible_name or view.caption or (type(view.content) == "string" and view.content) or "Terminal input",
                    masked = view.masked == true,
                }
                info.targets[#info.targets + 1] = target
                if entry.target == window.focus then
                    info.focus = target
                end
            end
        end
    end

    return {
        draw = function()
            info.handled = nil
            local rendered = false
            while true do
                local event = input:poll()
                if not event then
                    break
                end
                info.handled = window:event(event)
                -- Each event sees the focus and state produced by the previous one.
                render()
                rendered = true
            end
            if not rendered then
                render()
            end
            return window.wake
        end,
        info = function()
            return info
        end,
    }
end
