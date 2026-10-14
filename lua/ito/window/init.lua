local class = require("ito.class")
local Composition = require("ito.runtime.composition")
local Frame = require("ito.frame")
local host = require("ito.host")
local layout = require("ito.layout")
local Selection = require("ito.window.selection")
local Theme = require("ito.runtime.environment").Theme

local EDGE = 0.05

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
    local previous = self.focus
    self:settle(frame)
    -- Focus is known after controls register. Repaint a focus transition so
    -- only the active control draws its caret/highlight, including frame one.
    if root and previous ~= self.focus then
        frame.focusables, frame.scrollables, frame.key_handlers = {}, {}, {}
        root:draw(frame)
        self:settle(frame)
    end
    self.selection:capture_screen(self.screen)
    self:follow(frame)
    self.wake = frame.wake
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
            pane.target = entry.target
            panes[#panes + 1] = pane
        end
    end
    return panes
end

local function past(pane, row, height)
    local top, bottom = pane.top, pane.top + pane.height - 1
    if row < top or (row == top and top == 0) then
        return math.min(row - top, -1)
    end
    if row > bottom or (row == bottom and bottom == height - 1) then
        return math.max(row - bottom, 1)
    end
    return 0
end

local function inside(rect, row, col)
    return row >= rect.y and row < rect.y + rect.height and col >= rect.x and col < rect.x + rect.width
end

function Window:follow(frame)
    local pointer, selection = self.pointer, self.selection
    local pane = selection.range and selection.pane
    if not pointer or not pane or not pane.target then
        return
    end
    selection:drag(pointer.col, pointer.row)
    local _, height = self.screen:size()
    local rows = past(pane, pointer.row, height)
    if rows ~= 0 then
        pane.target:scroll(rows)
        frame:again(EDGE)
    end
end

function Window:settle(frame)
    local scoped = {}
    for _, focusable in ipairs(frame.focusables) do
        if focusable.scope == self.scope then
            scoped[#scoped + 1] = focusable
        end
    end
    local held, asked, first = nil, nil, nil
    local before, requested = self.requested or {}, {}
    for _, focusable in ipairs(scoped) do
        if focusable.target == self.focus then
            held = focusable
        end
        if focusable.wanted then
            first = first or focusable
            requested[focusable.target] = true
            if not before[focusable.target] then
                asked = focusable
            end
        end
    end
    local found = asked or held or first or scoped[1]
    self.focus = found and found.target
    self.focused = found and found.handle
    self.focusables, self.key_handlers, self.requested = scoped, frame.key_handlers, requested
    self.scrollables = frame.scrollables
end

function Window:unfocus()
    self.focused = nil
end

function Window:key(chord)
    if self.active == false then
        return false
    end
    if self.focused and self.focused(chord) == true then
        return true
    end
    for index = #(self.key_handlers or {}), 1, -1 do
        local entry = self.key_handlers[index]
        if entry.scope == self.scope and entry.handle(chord) == true then
            return true
        end
    end
    if chord.key == "tab" or chord.key == "backtab" then
        local step = chord.key == "backtab" and -1 or 1
        for index, entry in ipairs(self.focusables or {}) do
            if entry.target == self.focus then
                local next_entry = self.focusables[index + step]
                if not next_entry then
                    return false
                end
                self.focus, self.focused = next_entry.target, next_entry.handle
                return true
            end
        end
    end
    return false
end

function Window:is_focused(target)
    return self.active ~= false and self.focus == target
end

-- Hosts translate platform events once; controls and Lua own their meaning.
function Window:event(event)
    if event.type == "key" or event.type == "paste" then
        return self:key(event)
    elseif event.type == "focus" then
        self.active = event.focused
        return true
    elseif event.type == "resize" then
        return true
    elseif event.type == "mouse" then
        if event.kind == "down" and event.button == "left" then
            self:press(event.row, event.col)
        elseif event.kind == "drag" and event.button == "left" then
            self:drag(event.row, event.col)
        elseif event.kind == "up" and event.button == "left" then
            return true, self:release(event)
        elseif event.kind == "scroll_up" or event.kind == "scroll_down" then
            return self:wheel(event.row, event.col, event.kind == "scroll_up" and -3 or 3)
        else
            return false
        end
        return true
    end
    return false
end

function Window:scrollable_at(row, col)
    local found
    for index = #self.scrollables, 1, -1 do
        local entry = self.scrollables[index]
        if entry.scope == self.scope and inside(entry.rect, row, col) then
            if not found or entry.priority > found.priority then
                found = entry
            end
        end
    end
    return found and found.target
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
    for index = #(self.focusables or {}), 1, -1 do
        local entry = self.focusables[index]
        if entry.rect and inside(entry.rect, row, col) then
            self.focus, self.focused = entry.target, entry.handle
            break
        end
    end
    self.pointer = nil
    self.clicking = self.screen:clicked(row, col)
    self.selection:press(col, row, host.clock())
end

function Window:drag(row, col)
    self.pointer = { row = row, col = col }
    self.clicking = nil
    self.selection:drag(col, row)
end

function Window:release(event)
    self.pointer = nil
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
