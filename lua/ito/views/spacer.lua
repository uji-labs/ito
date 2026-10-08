local class = require("ito.class")
local View = require("ito.view")

local Spacer = class(View)

Spacer.standalone = true

function Spacer:init()
    View.init(self, {})
    self.weight = 1
end

return Spacer
