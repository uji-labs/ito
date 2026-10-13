local screen = require("support.screen")
local ito = require("ito")
local tty = require("ito.tty")

local function source()
    return ito.ImageSource.rgba(2, 1, string.char(255, 0, 0, 255, 0, 0, 255, 255))
end

local function wait_for(check)
    local deadline = os.clock() + 3
    repeat
        if check() then
            return
        end
    until os.clock() > deadline
    error("image worker did not finish")
end

describe("images", function()
    it("requires explicit graphics support and displays a configurable fallback", function()
        local s = screen.new(12, 4)
        local photo = source()
        local rows = s:show(function()
            return ito.Image(photo):alt("A photo"):width(12):height(4)
        end)
        assert.equal("  A photo", screen.trimmed(rows[2]))
        rows = s:show(function()
            return ito.Image(photo)
                :unsupported(function(status)
                    assert.equal("unsupported", status.phase)
                    assert.equal(photo, status.source)
                    return ito.Text("No graphics")
                end)
                :width(12)
                :height(4)
        end)
        assert.equal("No graphics", screen.trimmed(rows[2]))
        assert.equal("off", s.screen:image_capabilities().protocol)
    end)

    it("keeps general modifiers on a user-defined image view", function()
        local s = screen.new(20, 6)
        local photo = source()
        local tapped = 0
        local Photo = ito.view(function(props)
            return ito.Image(props.source):alt("photo"):content_alignment(ito.Alignment.top_leading):on_tap(function()
                tapped = tapped + 1
            end)
        end)
        local rows = s:show(function()
            return ito.VStack({
                Photo({ source = photo })
                    :width(10)
                    :height(4)
                    :align(ito.Alignment.leading)
                    :padding(1)
                    :overlay(ito.Text("x"), ito.Alignment.bottom_trailing),
            })
        end)
        assert.equal(" photo", screen.trimmed(rows[2]))
        assert.equal("         x", screen.trimmed(rows[4]))
        s:tap(1, 1)
        assert.equal(1, tapped)
    end)

    it("keeps image protocol characters out of text and styled snapshots", function()
        local s = tty.virtual(8, 4)
        s:configure_images({ protocol = "kitty", cell_width = 2, cell_height = 2 })
        local photo = source()
        local area = { x = 0, y = 0, width = 8, height = 4 }
        wait_for(function()
            s:clear()
            return s:image(photo, area) == "ready"
        end)
        s:paint(area, ito.TextStyle({ foreground = ito.Color.red, reverse = true, dim = true }))
        for row = 0, 3 do
            assert.equal(string.rep(" ", 8), s:text(row))
            for _, span in ipairs(s:spans(row)) do
                assert.is_nil(span.text:find("\27", 1, true))
                assert.same({}, span.modifiers)
            end
        end
        s:flush()
        s:suspend()
        s:resume()
        s:clear()
        assert.equal("ready", s:image(photo, area))
        s:flush()
        s:close()
    end)

    it("resolves async errors through the failed view and stops polling", function()
        local s = screen.new(20, 3)
        s.screen:configure_images({ protocol = "kitty" })
        local photo = ito.ImageSource.bytes("not a PNG or JPEG")
        local problem
        s:show(function()
            return ito.Image(photo):height(3):placeholder(ito.Text("Loading")):fallback(function(status)
                problem = status.error
                return ito.Text("Cannot load image")
            end)
        end)
        wait_for(function()
            s:rows()
            return problem ~= nil
        end)
        assert.equal(" Cannot load image", screen.trimmed(s:rows()[2]))
        assert.is_nil(s.frame.wake)
    end)

    it("validates image resources and transformation options", function()
        local photo = source()
        assert.has_error(function()
            ito.Image("path.png")
        end, "Image takes an ito.ImageSource")
        assert.has_error(function()
            ito.ImageSource.rgba(2, 2, "tiny")
        end)
        assert.has_error(function()
            ito.Image(photo):content_mode("fill")
        end)
        assert.has_error(function()
            ito.Image(photo):rotate(45)
        end)
        assert.has_error(function()
            ito.Image(photo):opacity(0 / 0)
        end)
        assert.has_error(function()
            ito.Image(photo):crop({ x = 0, y = 0, width = 0, height = 1 })
        end)
        assert.has_error(function()
            ito.Image(photo):sampling("linear")
        end)
        local view = ito.Image(photo):rotate(-90)
        assert.equal(270, view:options().rotation)
        assert.same({ phase = "ready", width = 2, height = 1 }, photo:status())
    end)

    it("measures images with cell proportions and per-view crop and rotation", function()
        local s = screen.new(20, 10)
        s.screen:configure_images({ protocol = "kitty", cell_width = 8, cell_height = 16 })
        local photo = source()
        local frame = ito.Frame(s.screen, screen.THEME)
        assert.equal(5, ito.Image(photo):measure(frame, 20))
        assert.equal(20, ito.Image(photo):rotate(90):measure(frame, 20))
        assert.equal(10, ito.Image(photo):crop({ x = 1, y = 0, width = 1, height = 1 }):measure(frame, 20))
        assert.equal(1, ito.Image(photo):content_mode(ito.ImageMode.original):measure(frame, 20))
        assert.equal(5, ito.Image(photo):measure(frame, 20))
    end)

    it("supports controlled zoom and pan while letting the parent own the wheel", function()
        local s = screen.new(20, 4)
        local photo, viewport = source(), ito.ImageViewport()
        local changes = 0
        s:show(function()
            return ito.ScrollView(ito.ImageViewer(photo):height(8):state(viewport):focused():on_change(function(value)
                assert.equal(viewport, value)
                changes = changes + 1
            end))
        end)
        s:press("+", "right", "down")
        assert.equal(1.25, viewport.zoom)
        assert.equal(0.1, viewport.x)
        assert.equal(0.1, viewport.y)
        assert.equal(3, changes)
        s:wheel(1, 1, 1)
        assert.equal(1.25, viewport.zoom)
        assert.is_false(s.window:key({ key = "+", ctrl = true }))
        s:press("0")
        assert.equal(1, viewport.zoom)
        assert.equal(0, viewport.x)
    end)

    it("captures wheel zoom only when configured, within the visible viewer", function()
        local s = screen.new(20, 4)
        local photo, viewport = source(), ito.ImageViewport()
        local scroll = ito.ScrollState()
        s:show(function()
            return ito.ScrollView(ito.VStack({
                ito.Text("before"),
                ito.ImageViewer(photo):height(4):state(viewport):wheel(ito.ImageWheel.zoom),
                ito.Text("after"),
            })):state(scroll)
        end)
        s:wheel(1, 1, -1)
        assert.is_true(viewport.zoom > 1)
        assert.equal(0, scroll.offset)
        s:wheel(0, 1, 1)
        assert.is_true(scroll.offset > 0)
        viewport:zoom_to(1000)
        assert.equal(64, viewport.zoom)
        viewport:pan_to(-5, 5)
        assert.equal(-1, viewport.x)
        assert.equal(1, viewport.y)
    end)

    it("eventually resolves more sources than the worker queue can hold", function()
        local sources = {}
        for index = 1, 24 do
            sources[index] = ito.ImageSource.bytes("invalid " .. index)
        end
        wait_for(function()
            local pending = false
            for _, item in ipairs(sources) do
                pending = item:status().phase == "loading" or pending
            end
            return not pending
        end)
        for _, item in ipairs(sources) do
            assert.equal("failed", item:status().phase)
        end
    end)
end)
