local root = arg[0]:match("^(.*)/[^/]*$") or "."
package.cpath = root .. "/../target/release/lib?.dylib;" .. root .. "/../target/release/lib?.so;" .. package.cpath

local ito = require("ito")
assert(arg[1], "usage: luajit examples/images.lua image.png")

local source = ito.ImageSource.file(arg[1])
local viewport = ito.ImageViewport()
local screen, input = ito.open()
local window = ito.Window(screen, function() end)
local context = { styles = {}, views = {} }
screen:configure_images({ protocol = "kitty", tmux = os.getenv("TMUX") ~= nil })

local function run()
    while true do
        screen:clear()
        local view = ito.VStack({
            ito.Text("+ / - zoom   arrows pan   0 reset   q quit"),
            ito.ImageViewer(source)
                :state(viewport)
                :focused()
                :wheel(ito.ImageWheel.zoom)
                :alt(arg[1])
                :placeholder(ito.Text("Loading image…"))
                :fallback(function(status)
                    return ito.Text(status.error or "Image preview unavailable"):wrap()
                end)
                :grow(),
            ito.Text(string.format("%.2fx", viewport.zoom)),
        })
        local frame = window:render(view, context)
        screen:flush()
        local event = input:read(frame.wake)
        if event and event.type == "key" then
            if event.key == "q" or event.key == "esc" or (event.ctrl and event.key == "c") then
                break
            end
            window:key(event)
        elseif event and event.type == "mouse" then
            if event.kind == "scroll_up" then
                window:wheel(event.row, event.col, -1)
            elseif event.kind == "scroll_down" then
                window:wheel(event.row, event.col, 1)
            end
        end
    end
end

local ok, problem = xpcall(run, debug.traceback)
screen:close()
assert(ok, problem)
