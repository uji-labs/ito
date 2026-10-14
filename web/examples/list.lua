local ito = require("ito")
local draft = ito.state("")
local revision = ito.state(0)
local tasks = {
    { title = "Take a walk", done = ito.state(true), id = 1 },
    { title = "Make something small", done = ito.state(false), id = 2 },
    { title = "Call an old friend", done = ito.state(false), id = 3 },
}
local next_id = 4

local function add()
    if not draft.value:match("%S") then
        return
    end
    tasks[#tasks + 1] = { title = draft.value, done = ito.state(false), id = next_id }
    next_id = next_id + 1
    draft.value = ""
    revision.value = revision.value + 1
end

return function()
    local _ = revision.value
    local rows, complete = {}, 0
    for _, task in ipairs(tasks) do
        if task.done.value then
            complete = complete + 1
        end
        rows[#rows + 1] = ito.Checkbox(task.title, task.done):id(task.id)
    end
    return ito.VStack({
        ito.Text("ONE DAY AT A TIME"):dim(),
        ito.Heading("A few good things."):wrap(),
        ito.Text(complete .. " of " .. #tasks .. " done"):dim(),
        ito.VStack(rows):spacing(1):padding({ top = 1, bottom = 1 }),
        ito.HStack({
            ito.TextField(draft):placeholder("Something worth doing"):accessibility_label("New task"):on_submit(add):grow(),
            ito.Button("Add", add):reverse(),
        }):spacing(1),
    })
        :spacing(1)
        :padding(1)
        :border(ito.theme().borders.rounded)
end
