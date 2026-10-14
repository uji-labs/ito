local text = require("ito.text")

local SINGLE = "^" .. text.CHAR .. "$"

local EDITS = {
    left = "left",
    right = "right",
    home = "home",
    ["end"] = "tail",
    backspace = "backspace",
    delete = "delete_forward",
}

local M = {}

function M.typed(chord)
    return not chord.ctrl and not chord.alt and not chord.meta and type(chord.key) == "string" and chord.key:match(SINGLE) ~= nil
end

function M.edit(line, key)
    local edit = EDITS[key]
    if not edit then
        return false
    end
    line[edit](line)
    return true
end

return M
