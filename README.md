# Ito

A declarative UI library for Lua.

Heavily inspired by SwiftUI.

[Try it in the browser](https://uji.sh/ito/) — an interactive workshop with a live preview.

```lua
local ito = require("ito")
local quantity = ito.state(1)
local wrapped = ito.state(false)
local ordered = ito.state(false)
local price = 18
local gift_wrap = 3

return function()
    local total = quantity.value * price + (wrapped.value and gift_wrap or 0)
    return ito.VStack({
        ito.Text("FIELD\nNOTES"):bold():padding(1):foreground(ito.rgb(0xfff5de)):background(ito.rgb(0xc65036)):align(ito.Alignment.center),
        ito.Text("THE SMALL GOODS SHOP"):dim(),
        ito.HStack({
            ito.Heading("Room for ideas."):wrap():grow(),
            ito.Text("$" .. price):bold(),
        }):spacing(1),
        ito.Text("A pocket notebook. For things you don't want to forget."):dim():wrap(),
        ito.HStack({
            ito.Button("−", function()
                quantity.value = math.max(1, quantity.value - 1)
            end):accessibility_label("Fewer notebooks"),
            ito.Text(tostring(quantity.value)),
            ito.Button("+", function()
                quantity.value = math.min(9, quantity.value + 1)
            end):accessibility_label("More notebooks"),
        }):spacing(1),
        ito.Checkbox("Wrap it as a gift (+$" .. gift_wrap .. ")", wrapped),
        ito.Button(ordered.value and "Added. Thank you!" or "Add to bag · $" .. total, function()
            ordered.value = not ordered.value
        end):reverse(),
    })
        :spacing(1)
        :padding(1)
        :border(ito.theme().borders.rounded)
end
```
