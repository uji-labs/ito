local root = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = table.concat({
    root .. "/?.lua",
    root .. "/?/init.lua",
    root .. "/vendor/?.lua",
    root .. "/vendor/?/init.lua",
    package.path,
}, ";")
package.cpath = table.concat({
    root .. "/../target/release/lib?.dylib",
    root .. "/../target/release/lib?.so",
    package.cpath,
}, ";")

local filters = { unpack(arg) }

local function wanted(name)
    if #filters == 0 then
        return true
    end
    for _, filter in ipairs(filters) do
        if name:find(filter, 1, true) then
            return true
        end
    end
    return false
end

local function joined(names, name)
    local out = { unpack(names) }
    out[#out + 1] = name
    return out
end

local function collect(path)
    local tests = {}
    local block = { names = {}, before = {}, after = {} }
    local env = setmetatable({ assert = require("luassert") }, { __index = _G })
    function env.describe(name, body)
        local parent = block
        block = { parent = parent, names = joined(parent.names, name), before = {}, after = {} }
        body()
        block = parent
    end
    function env.it(name, body)
        tests[#tests + 1] = { name = table.concat(joined(block.names, name), " "), body = body, block = block }
    end
    function env.before_each(fn)
        block.before[#block.before + 1] = fn
    end
    function env.after_each(fn)
        block.after[#block.after + 1] = fn
    end
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
    return tests
end

local function hooks(block, field, into)
    if block.parent then
        hooks(block.parent, field, into)
    end
    for _, fn in ipairs(block[field]) do
        into[#into + 1] = fn
    end
    return into
end

local passed, failed = 0, {}
local listing = io.popen('ls "' .. root .. '"/*_spec.lua')
for path in listing:lines() do
    local spec = path:match("([^/]+)_spec%.lua$")
    for _, test in ipairs(collect(path)) do
        local name = spec .. "::" .. test.name
        if wanted(name) then
            local ok, err = xpcall(function()
                for _, fn in ipairs(hooks(test.block, "before", {})) do
                    fn()
                end
                test.body()
                for _, fn in ipairs(hooks(test.block, "after", {})) do
                    fn()
                end
            end, debug.traceback)
            if ok then
                passed = passed + 1
                print("PASS " .. name)
            else
                failed[#failed + 1] = { name = name, err = err }
                print("FAIL " .. name)
            end
        end
    end
end
listing:close()

for _, failure in ipairs(failed) do
    print("\n--- " .. failure.name .. "\n" .. tostring(failure.err))
end
print(string.format("\n%d tests: %d passed, %d failed", passed + #failed, passed, #failed))
os.exit(#failed == 0 and 0 or 1)
