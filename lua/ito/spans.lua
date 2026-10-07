local text = require("ito.text")

local SPACE = (" "):byte()

local M = {}

local function source(line)
    local parts = {}
    for index, span in ipairs(line) do
        parts[index] = span[1]
    end
    return table.concat(parts)
end

local function fields(line)
    local out = {}
    for key, field in pairs(line) do
        if type(key) ~= "number" then
            out[key] = field
        end
    end
    return out
end

local function bytes(value, width)
    local rows, from, last = {}, 1, #value
    while from <= last do
        local stop = math.min(from + width - 1, last)
        local after = stop + 1
        local first = value:sub(from, stop):find("[^ ]")
        first = first and from + first - 1
        if stop < last and first then
            if value:byte(after) == SPACE then
                after = after + 1
            else
                local space = value:sub(first, stop):match("^.*() ")
                if space then
                    stop, after = first + space - 2, first + space
                end
            end
        end
        rows[#rows + 1] = { from, stop }
        from = after
    end
    return rows
end

local function characters(value, width)
    local chars, starts, at = {}, {}, 1
    for char in value:gmatch(text.CHAR) do
        chars[#chars + 1] = char
        starts[#starts + 1] = at
        at = at + #char
    end
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
        rows[#rows + 1] = { starts[from], starts[stop] + #chars[stop] - 1 }
        from = after
    end
    return rows
end

local function copied(map)
    local out = {}
    for key, field in pairs(map) do
        out[key] = field
    end
    return out
end

local function piece(span, value)
    local out = copied(span)
    out[1] = value
    return out
end

local function sliced(line, ranges)
    local extra = fields(line)
    local rows, at, offset = {}, 1, 0
    for index, range in ipairs(ranges) do
        local from, stop = range[1], range[2]
        while at <= #line and offset + #line[at][1] < from do
            offset = offset + #line[at][1]
            at = at + 1
        end
        local row = copied(extra)
        local next, start = at, offset
        while next <= #line and start < stop do
            local span = line[next]
            local first, last = start + 1, start + #span[1]
            local low, high = math.max(first, from), math.min(last, stop)
            if low == first and high == last then
                row[#row + 1] = span
            elseif low <= high then
                row[#row + 1] = piece(span, span[1]:sub(low - start, high - start))
            end
            start, next = last, next + 1
        end
        rows[index] = row
    end
    return rows
end

function M.wrap(line, width)
    local value = source(line)
    if width <= 0 or value == "" then
        return { line }
    end
    if text.width(value) <= width then
        local row = fields(line)
        for index, span in ipairs(line) do
            row[index] = span
        end
        return { row }
    end
    local ascii = not value:find("[\128-\255]")
    return sliced(line, ascii and bytes(value, width) or characters(value, width))
end

return M
