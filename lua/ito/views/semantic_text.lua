local class = require("ito.class")
local Text = require("ito.views.text")

-- The terminal expresses hierarchy through emphasis; other renderers can
-- give these same views their native heading and numeric typography.
local Heading = class(Text)
function Heading:init(content)
    Text.init(self, content)
    self:bold()
end

local Metric = class(Text)
function Metric:init(value)
    Text.init(self, tostring(value))
    self:bold()
end

return { Heading = Heading, Metric = Metric }
