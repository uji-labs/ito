local screen = require("support.screen")

describe("window", function()
    local kit = require("ito")

    it("sends keys to the focused control, wheel turns to what is under the pointer, and clicks to their target", function()
        local s = screen.new(20, 4)
        local value = kit.state("")
        local taps = 0
        local scroll = kit.ScrollState()
        local lines = {}
        for index = 1, 10 do
            lines[index] = { { "row " .. index } }
        end
        s:show(function()
            return kit.VStack({
                kit.TextField(value):focused(),
                kit.Text("[tap]"):on_tap(function()
                    taps = taps + 1
                end),
                kit.ScrollView(kit.Lines(lines)):state(scroll):height(2),
            })
        end)
        local window = s.window
        assert.is_true(window:key({ key = "x", ctrl = false, alt = false, shift = false }))
        s:rows()
        assert.equal("x", value.value)
        assert.is_true(window:wheel(2, 1, 3))
        assert.equal("row 4", screen.trimmed(s:rows()[3]))
        assert.is_false(window:wheel(0, 1, 3))
        window:press(1, 1)
        assert.is_nil(window:release({}))
        assert.equal(1, taps)
    end)

    it("selects text with a drag, gives it back on release, and highlights it", function()
        local s = screen.new(20, 2)
        s:show(function()
            return kit.ZStack({
                alignment = kit.Alignment.top_leading,
                kit.VStack({ kit.Text("hello world"), kit.Text("second") }),
                kit.SelectionHighlight(),
            })
        end)
        local window = s.window
        window:press(0, 0)
        window:drag(0, 5)
        s:rows()
        assert.same({ "reverse" }, s.screen:spans(0)[1].modifiers)
        assert.equal("hello", window:release({}))
    end)
end)
