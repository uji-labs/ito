local ito = require("ito")
local count = ito.state(4)
local goal = 8

return function()
    return ito.VStack({
        ito.Text("DAILY PRACTICE"):dim(),
        ito.Heading("Make room for reading."):wrap(),
        ito.Text("A few pages at a time adds up."):dim():wrap(),
        ito.HStack({
            ito.Metric(count.value),
            ito.Text("of " .. goal .. " pages"):dim(),
        })
            :spacing(1)
            :padding({ top = 1, bottom = 1 }),
        ito.Progress(count.value / goal):label("Daily reading goal"),
        ito.HStack({
            ito.Button("−", function()
                count.value = math.max(0, count.value - 1)
            end):accessibility_label("One fewer page"),
            ito.Button("One more page", function()
                count.value = math.min(goal, count.value + 1)
            end)
                :reverse()
                :grow()
                :disabled(count.value >= goal),
        })
            :spacing(1)
            :padding({ top = 1 }),
        ito.Text(count.value >= goal and "A good day's reading." or "No rush. Just keep turning the page.")
            :dim()
            :wrap()
            :padding({ top = 1 }),
    })
        :spacing(1)
        :padding(1)
        :border(ito.theme().borders.rounded)
end
