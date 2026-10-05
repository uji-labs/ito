local class = require("ito.class")
local host = require("ito.host")
local runtime = require("ito.runtime")
local View = require("ito.view")

local SubcomposeLayout = class(View)

function SubcomposeLayout:init(build, opts)
    View.init(self, {})
    if type(build) ~= "function" then
        error("ito.SubcomposeLayout needs a function that builds a view for its room", 3)
    end
    self.build = build
    self.failed = opts and opts.failed
end

function SubcomposeLayout:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    return self
end

function SubcomposeLayout:content(room)
    local element = runtime.Build({ build = self.build, value = room })
    local ok, view = pcall(self.composition.place, self.composition, element, self.node, 1, self.environment)
    if ok then
        return view
    end
    if self.failed then
        self.failed(tostring(view))
    else
        host.report(tostring(view))
    end
end

function SubcomposeLayout:content_height(frame, width)
    local view = self:content({ width = width, height = math.huge })
    return view and view:measure(frame, width) or 0
end

function SubcomposeLayout:content_width(frame)
    local view = self:content({})
    return view and view:natural_width(frame)
end

function SubcomposeLayout:arrange(frame, inner)
    local view = self:content({ width = inner.width, height = inner.height })
    self.composed = { view }
    if view then
        view:place(frame, inner)
    end
    self.node:sweep(self.composition.generation)
end

return SubcomposeLayout
