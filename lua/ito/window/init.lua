local class = require("ito.class")
local Composition = require("ito.runtime.composition")
local Frame = require("ito.frame")
local host = require("ito.host")
local layout = require("ito.layout")
local Selection = require("ito.window.selection")
local Theme = require("ito.runtime.environment").Theme

local Window = class()

function Window:init(screen, invalidate)
    self.screen = screen
    self.composition = Composition(invalidate)
    self.selection = Selection()
    self.scrollables = {}
    self.pane_of = setmetatable({}, { __mode = "k" })
end

function Window:place(element, ctx)
    local width, height = self.screen:size()
    local frame = Frame(self.screen, ctx)
    frame.window = self
    Theme:set(ctx)
    local root = self.composition:compose(Theme:provide(ctx, element))
    if root then
        root:place(frame, layout.rect(0, 0, width, height))
    end
    return root, frame
end

function Window:draw(root, frame)
    if root then
        root:draw(frame)
    end
    self.selection:capture_screen(self.screen)
    self:settle(frame)
    return frame
end

function Window:render(element, ctx)
    return self:draw(self:place(element, ctx))
end

function Window:panes(frame)
    local panes = {}
    for _, entry in ipairs(frame.scrollables) do
        local scroll, viewport = entry.state, entry.state and entry.state.viewport
        if viewport and entry.scope == self.scope then
            local key = tostring(frame.ctx) .. ":" .. viewport.width .. ":" .. (viewport.jumps or 0)
            local pane = self.pane_of[scroll]
            if not pane or pane.key ~= key then
                pane = { key = key }
                self.pane_of[scroll] = pane
            end
            pane.top, pane.height, pane.shift = viewport.top, viewport.height, viewport.top - viewport.first
            panes[#panes + 1] = pane
        end
    end
    return panes
end

function Window:settle(frame)
    local scoped = {}
    for _, focusable in ipairs(frame.focusables) do
        if focusable.scope == self.scope then
            scoped[#scoped + 1] = focusable
        end
    end
    local found
    for _, focusable in ipairs(scoped) do
        if focusable.target == self.focus then
            found = focusable
        end
    end
    if not found then
        for _, focusable in ipairs(scoped) do
            if focusable.wanted then
                found = focusable
                break
            end
        end
    end
    found = found or scoped[1]
    self.focus = found and found.target
    self.focused = found and found.handle
    self.scrollables = frame.scrollables
    self.wake = frame.wake
end

function Window:unfocus()
    self.focused = nil
end

function Window:key(chord)
    return self.focused ~= nil and self.focused(chord) == true
end

function Window:scrollable_at(row, col)
    for index = #self.scrollables, 1, -1 do
        local entry = self.scrollables[index]
        local rect = entry.rect
        if row >= rect.y and row < rect.y + rect.height and col >= rect.x and col < rect.x + rect.width then
            return entry.target
        end
    end
end

function Window:wheel(row, col, rows)
    local target = row and col and self:scrollable_at(row, col)
    if target then
        target:scroll(rows)
        return true
    end
    return false
end

function Window:press(row, col)
    self.clicking = self.screen:clicked(row, col)
    self.selection:press(col, row, host.clock())
end

function Window:drag(row, col)
    self.clicking = nil
    self.selection:drag(col, row)
end

function Window:release(event)
    local click = self.clicking
    self.clicking = nil
    local copied = self.selection:release()
    if copied then
        return copied
    end
    if click then
        click(event)
    end
end

return Window
