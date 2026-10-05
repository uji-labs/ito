local M = {}

function M.is_view(value)
    return type(value) == "table" and type(value.compose) == "function"
end

return M
