local class = require("ito.class")
local placement = require("ito.toolbar.placement")
local runtime = require("ito.runtime")

local Item = class()

local function callable(value)
    local meta = type(value) == "table" and getmetatable(value)
    return type(value) == "function" or (meta and meta.__call ~= nil)
end

function Item:init(at, content)
    if not placement.is(at) then
        error("ToolbarItem takes one of ito.ToolbarPlacement first", 3)
    end
    if not callable(content) then
        error("ToolbarItem takes a view, or a function that returns one, second", 3)
    end
    self.placement = at
    self.body = runtime.body(content)
end

function Item:id(...)
    self.key = runtime.identity(...)
    return self
end

function Item.is(value)
    return getmetatable(value) == Item
end

return Item
