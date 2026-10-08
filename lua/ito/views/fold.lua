local class = require("ito.class")
local layout = require("ito.layout")
local runtime = require("ito.runtime")
local View = require("ito.view")

local Fold = class(View)

Fold.live = true

function Fold:init(content, opts)
    View.init(self, {})
    opts = opts or {}
    if opts.rows ~= nil and (type(opts.rows) ~= "number" or opts.rows < 0 or opts.rows % 1 ~= 0) then
        error("Fold takes a whole number of rows, not " .. tostring(opts.rows), 3)
    end
    if opts.more ~= nil and type(opts.more) ~= "function" then
        error("Fold takes a function that builds the view under the cut, not a " .. type(opts.more), 3)
    end
    self.inside, self.limit, self.more = content, opts.rows, opts.more
end

function Fold:compose(composition, node, environment)
    node.lazy = true
    self.composition, self.node, self.environment = composition, node, environment
    return self
end

function Fold:parts(frame, width)
    local content = self.composition:place(self.inside, self.node, 1, self.environment)
    if not content then
        return nil, 0
    end
    local total = content:measure(frame, width)
    if not self.limit or total <= self.limit then
        return content, total
    end
    local hidden = total - self.limit
    local more = self.more and self.composition:place(runtime.Build({ build = self.more, value = hidden }), self.node, 2, self.environment)
    return content, self.limit, more
end

function Fold:content_height(frame, width)
    local _, shown, more = self:parts(frame, width)
    return shown + (more and more:measure(frame, width) or 0)
end

function Fold:arrange(frame, inner)
    local content, shown, more = self:parts(frame, inner.width)
    self.composed = { content, more }
    if content then
        content:place(frame, layout.rect(inner.x, inner.y, inner.width, math.min(shown, inner.height)))
    end
    if more then
        local top = math.min(shown, inner.height)
        more:place(frame, layout.rect(inner.x, inner.y + top, inner.width, inner.height - top))
    end
    self.node:sweep(self.composition.generation)
end

return Fold
