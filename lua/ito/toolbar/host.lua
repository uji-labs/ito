local Board = require("ito.toolbar.board")
local class = require("ito.class")
local host = require("ito.host")
local runtime = require("ito.runtime")
local View = require("ito.view")

local Host = class(View)

Host.live = true

function Host:init(content)
    View.init(self, { content })
end

function Host:content_height(frame, width)
    local content = self.composed[1]
    return content and content:measure(frame, width) or 0
end

function Host:content_width(frame)
    local content = self.composed[1]
    return content and content:natural_width(frame)
end

local function gather(view, found, root)
    if not root and getmetatable(view) == Host then
        return
    end
    for _, items in ipairs(view.declared or {}) do
        found[#found + 1] = { from = view, items = items }
    end
    for _, child in ipairs(view.composed or {}) do
        gather(child, found, false)
    end
    for _, extra in ipairs(view.extras or {}) do
        if extra.view then
            gather(extra.view, found, false)
        end
    end
end

function Host:compose(composition, node, environment)
    local memo = node.memo
    if memo.outer ~= environment then
        memo.outer = environment
        memo.board = {}
        memo.inner = setmetatable({ [Board] = memo.board }, { __index = environment })
    end
    local board = memo.board
    board.items, board.shown = {}, {}
    self.board = board
    View.compose(self, composition, node, memo.inner)
    local declarations = {}
    gather(self, declarations, true)
    for number, declaration in ipairs(declarations) do
        for index, item in ipairs(declaration.items) do
            if item then
                local key = item.key
                if key == nil then
                    key = runtime.identity(declaration.from.memo, number, index)
                end
                board.items[#board.items + 1] = { item = item, key = key }
            end
        end
    end
    return self
end

function Host:place(frame, rect)
    View.place(self, frame, rect)
    local missing = self.memo.missing or {}
    self.memo.missing = missing
    local wanted = {}
    for _, entry in ipairs(self.board.items) do
        wanted[entry.item.placement] = true
    end
    for at in pairs(wanted) do
        if self.board.shown[at] then
            missing[at] = nil
        elseif not missing[at] then
            missing[at] = true
            host.report("toolbar: nothing shows the items placed at " .. at.name)
        end
    end
    for at in pairs(missing) do
        if not wanted[at] then
            missing[at] = nil
        end
    end
end

return Host
