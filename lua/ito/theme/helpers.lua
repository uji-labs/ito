local text = require("ito.text")

local M = {}

function M.measure(_, value)
    return text.width(value)
end

function M.clip(_, value, width)
    return text.clip(value, width)
end

function M.pad(_, value, width)
    return text.pad(value, width)
end

function M.first(_, value, count)
    local chars = text.chars(value)
    return table.concat(chars, "", 1, math.min(#chars, count))
end

function M.chunks(_, value, width)
    return text.wrap(value, width)
end

function M.wrap(ctx, value, opts)
    local prefix = opts.prefix or ""
    local width = opts.width or ctx.width
    local trailing = opts.fill and 1 or 0
    local inner = math.max(width - text.width(prefix) - trailing, 0)
    local lines = {}
    for _, chunk in ipairs(text.wrap(value, inner)) do
        if opts.fill then
            local pad = string.rep(" ", math.max(inner - text.width(chunk), 0))
            lines[#lines + 1] = { { prefix .. chunk .. " " .. pad, opts.style } }
        else
            lines[#lines + 1] = { { prefix .. chunk, opts.style } }
        end
    end
    return lines
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
    return { { before, styles.text }, { ctx.symbols.cursor, styles.cursor }, { after, styles.text } }
end

function M.fold(ctx, content, opts)
    local width = opts.width or ctx.width
    local limit = opts.limit
    local rows, hidden = {}, 0
    for _, raw in ipairs(text.lines(content)) do
        local shown = limit and text.clip(raw, math.max(limit - #rows, 0) * width) or raw
        for _, chunk in ipairs(shown == "" and raw ~= "" and {} or text.wrap(shown, width)) do
            rows[#rows + 1] = chunk
        end
        if #shown < #raw then
            hidden = hidden + math.ceil(text.width(raw:sub(#shown + 1)) / width)
        end
    end
    if limit then
        hidden = hidden + math.max(#rows - limit, 0)
        for index = #rows, limit + 1, -1 do
            rows[index] = nil
        end
    end
    return rows, hidden
end

return M
