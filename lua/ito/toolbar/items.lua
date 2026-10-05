local Board = require("ito.toolbar.board")
local class = require("ito.class")
local host = require("ito.host")
local placement = require("ito.toolbar.placement")
local stack = require("ito.views.stack")
local View = require("ito.view")

local Guard = class()

function Guard:init(entry)
    self.entry = entry
    self.key = entry.key
end

function Guard:compose(composition, node, environment)
    local ok, view = pcall(composition.place, composition, self.entry.item.body(), node, 1, environment)
    if ok then
        node.memo.failure = nil
        return view
    end
    local problem = "toolbar item: " .. tostring(view)
    if node.memo.failure ~= problem then
        node.memo.failure = problem
        host.report(problem)
    end
    return nil
end

local Items = class(View)

function Items:init(at, arrange)
    View.init(self, {})
    if not placement.is(at) then
        error("ToolbarItems takes one of ito.ToolbarPlacement first", 3)
    end
    self.placement = at
    self.arranged = arrange or stack.VStack
end

function Items:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    self.board = environment[Board]
    return self
end

function Items:built()
    if self.view ~= nil then
        return self.view or nil
    end
    local views = {}
    if self.board then
        self.board.shown[self.placement] = true
        for _, entry in ipairs(self.board.items) do
            if entry.item.placement == self.placement then
                views[#views + 1] = Guard(entry)
            end
        end
    end
    local element = #views > 0 and self.arranged(views)
    self.view = element and self.composition:place(element, self.node, 1, self.environment) or false
    self.composed = { self.view or nil }
    self.node:sweep(self.composition.generation)
    return self.view or nil
end

function Items:content_height(frame, width)
    local view = self:built()
    return view and view:measure(frame, width) or 0
end

function Items:content_width(frame)
    local view = self:built()
    return view and view:natural_width(frame) or 0
end

function Items:arrange(frame, inner)
    local view = self:built()
    if view then
        view:place(frame, inner)
    end
end

return Items
