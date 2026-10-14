local ito = require("ito")
local phase = ito.state("choose")
local selected = ito.state(1)
local draft = ito.state("")
local saved = ito.state("")
local items = { "Morning walk", "Read a chapter", "Make something" }

local function edit()
    draft.value = items[selected.value]
    phase.value = "edit"
end

return function()
    local content
    if phase.value == "choose" then
        content = ito.VStack({
            ito.Text("CHOOSE AN ITEM"):bold(),
            ito.List(items, function(item, index, active)
                local row = ito.Text((active and "› " or "  ") .. item):on_tap(function()
                    selected.value = index
                    edit()
                end)
                return active and row:bold() or row
            end)
                :selection(selected)
                :on_choose(edit)
                :focused()
                :height(3),
            ito.Text("↑ ↓ to choose · Enter to edit"):dim():wrap(),
        }):spacing(1)
    elseif phase.value == "edit" then
        content = ito.VStack({
            ito.Text("EDIT NAME"):bold(),
            ito.TextField(draft)
                :label("Name")
                :focused()
                :on_submit(function(value)
                    if value:match("%S") then
                        phase.value = "review"
                    end
                end)
                :on_cancel(function()
                    phase.value = "choose"
                end),
            ito.Text("Enter to review · Esc to cancel"):dim():wrap(),
        }):spacing(1)
    elseif phase.value == "review" then
        content = ito.VStack({
            ito.Text("REVIEW"):bold(),
            ito.Text(draft.value):wrap(),
            ito.Button("Save name", function()
                saved.value = draft.value
                phase.value = "done"
            end):focused(),
            ito.Text("Enter to save · Esc to keep editing"):dim():wrap(),
        })
            :spacing(1)
            :on_key(function(key)
                if key.key == "esc" then
                    phase.value = "edit"
                    return true
                end
                return false
            end)
    else
        content = ito.VStack({
            ito.Text("SAVED"):bold(),
            ito.Text(saved.value):wrap(),
            ito.Button("Start again", function()
                phase.value = "choose"
            end):focused(),
        }):spacing(1)
    end
    return ito.VStack({
        ito.Text("A small editing flow"):bold(),
        content:id(phase.value),
    })
        :spacing(2)
        :padding(1)
end
