local text = require("ito.text")

local M = {}

function M.measure(_, value)
    return text.width(value)
end

function M.first(_, value, count)
    local chars = text.chars(value)
    return table.concat(chars, "", 1, math.min(#chars, count))
end

function M.typed(ctx, field, styles)
    local value = field.text
    local before, after
    if field.hidden then
        local at = text.length(value:sub(1, field.cursor))
        before = string.rep(ctx.symbols.mask, at)
        after = string.rep(ctx.symbols.mask, text.length(value) - at)
    else
        before = value:sub(1, field.cursor)
        after = value:sub(field.cursor + 1)
    end
    return { { before, styles.text }, { ctx.symbols.cursor, styles.cursor, cursor = true }, { after, styles.text } }
end

return M
