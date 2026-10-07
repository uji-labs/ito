local text = require("ito.text")

local M = {}

local function letters(line)
    local chars, owners = {}, {}
    for index, span in ipairs(line) do
        for char in span[1]:gmatch(text.CHAR) do
            chars[#chars + 1] = char
            owners[#owners + 1] = index
        end
    end
    return chars, owners
end

local function breaks(chars, width)
    local rows, from = {}, 1
    while from <= #chars do
        local used, stop, space, words = 0, from - 1, nil, false
        while stop < #chars and used + text.width(chars[stop + 1]) <= width do
            stop = stop + 1
            used = used + text.width(chars[stop])
            if chars[stop] ~= " " then
                words = true
            elseif words then
                space = stop
            end
        end
        local after = stop + 1
        if stop < #chars and words and chars[after] == " " then
            after = after + 1
        elseif stop < #chars and space then
            stop, after = space - 1, space + 1
        end
        if stop < from then
            stop, after = from, from + 1
        end
        rows[#rows + 1] = { from, stop }
        from = after
    end
    return rows
end

local function piece(span, value)
    local out = {}
    for key, field in pairs(span) do
        out[key] = field
    end
    out[1] = value
    return out
end

local function row(line, chars, owners, from, stop)
    local out = {}
    for key, field in pairs(line) do
        if type(key) ~= "number" then
            out[key] = field
        end
    end
    local start = from
    for at = from, stop do
        if at == stop or owners[at + 1] ~= owners[at] then
            out[#out + 1] = piece(line[owners[at]], table.concat(chars, "", start, at))
            start = at + 1
        end
    end
    return out
end

function M.wrap(line, width)
    local chars, owners = letters(line)
    if width <= 0 or #chars == 0 then
        return { line }
    end
    local out = {}
    for index, range in ipairs(breaks(chars, width)) do
        out[index] = row(line, chars, owners, range[1], range[2])
    end
    return out
end

return M
