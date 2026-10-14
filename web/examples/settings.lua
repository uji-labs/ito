local ito = require("ito")
local quiet = ito.state(true)
local reminders = ito.state(false)
local minutes = ito.state(25)

return function()
    return ito.VStack({
        ito.Text("YOUR OWN PACE"):dim(),
        ito.Heading("A little more focus."):wrap(),
        ito.Text("Make this space work for you."):dim():wrap(),
        ito.VStack({
            ito.Toggle("Quiet hours", quiet):description("Keep the interruptions for later."),
            ito.Toggle("Gentle reminders", reminders):description("A nudge when it's time for a break."),
        })
            :spacing(2)
            :padding({ top = 1, bottom = 1 }),
        ito.Slider(minutes, { min = 5, max = 60, step = 5 }):label("Focus session"):suffix(" minutes"),
        ito.Text(quiet.value and "Your quiet corner is ready." or "You're open to the world."):dim():wrap():padding({ top = 1 }),
    })
        :spacing(1)
        :padding(1)
        :border(ito.theme().borders.rounded)
end
