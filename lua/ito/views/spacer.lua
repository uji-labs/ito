local class = require("ito.class")
local View = require("ito.view")

local Spacer = class(View)

function Spacer:init()
    View.init(self, {})
    self.weight = 1
end

return Spacer
