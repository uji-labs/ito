local text = require("ito.text")

local M = {}

function M.clock()
    return os.clock()
end

function M.report(message)
    io.stderr:write(message, "\n")
end

function M.setup(opts)
    if opts.width then
        text.width = opts.width
    end
    if opts.clock then
        M.clock = opts.clock
    end
    if opts.report then
        M.report = opts.report
    end
end

return M
