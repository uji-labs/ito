local screen = require("support.screen")

describe("toolbars", function()
    local ito = require("ito")
    local trimmed = screen.trimmed
    local placement = ito.ToolbarPlacement

    local reported
    before_each(function()
        reported = {}
        ito.setup({
            report = function(message)
                reported[#reported + 1] = message
            end,
        })
    end)

    local function bars(body)
        return ito.ToolbarHost(ito.VStack({
            ito.HStack({
                ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
                ito.Spacer(),
                ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
            }),
            body:grow(),
            ito.ToolbarItems(placement.keyboard),
            ito.Text("input"),
            ito.ToolbarItems(placement.bottom_bar),
        }))
    end

    local function text(value)
        return function()
            return ito.Text(value)
        end
    end

    it("shows each item in the section its placement names, in the order they were declared", function()
        local s = screen.new(30, 7)
        local rows = s:show(function()
            return bars(ito.Text("body"):toolbar({
                ito.ToolbarItem(placement.keyboard, text("hint")),
                ito.ToolbarItem(placement.bottom_bar, text("first")),
            })):toolbar({
                ito.ToolbarItem(placement.top_bar_leading, text("left")),
                ito.ToolbarItem(placement.top_bar_trailing, text("right")),
                ito.ToolbarItem(placement.bottom_bar, text("own")),
            })
        end)
        assert.equal("left" .. string.rep(" ", 21) .. "right", rows[1])
        assert.equal("body", trimmed(rows[2]))
        assert.equal("hint", trimmed(rows[4]))
        assert.equal("input", trimmed(rows[5]))
        assert.equal("own", trimmed(rows[6]))
        assert.equal("first", trimmed(rows[7]))
    end)

    it("takes the height of its content inside a stack", function()
        local s = screen.new(20, 4)
        local rows = s:show(function()
            return ito.VStack({
                ito.ToolbarHost(ito.VStack({ ito.Text("inner"), ito.ToolbarItems(placement.bottom_bar) })):toolbar({
                    ito.ToolbarItem(placement.bottom_bar, text("bar")),
                }),
                ito.Text("after"),
            })
        end)
        assert.equal("inner", trimmed(rows[1]))
        assert.equal("bar", trimmed(rows[2]))
        assert.equal("after", trimmed(rows[3]))
    end)

    it("gives a section no room while it has no items", function()
        local s = screen.new(20, 3)
        local rows = s:show(function()
            return bars(ito.Text("body"))
        end)
        assert.equal("body", trimmed(rows[1]))
        assert.equal("input", trimmed(rows[3]))
    end)

    it("keeps an item's state across frames, and leaves out one that draws nothing", function()
        local count
        local Counter = ito.view(function()
            count = ito.state(0)
            return ito.Text("n" .. count.value)
        end)
        local Empty = ito.view(function()
            return false
        end)
        local s = screen.new(20, 3)
        s:show(function()
            return bars(ito.Text("body")):toolbar({
                ito.ToolbarItem(placement.bottom_bar, Empty),
                ito.ToolbarItem(placement.bottom_bar, Counter),
            })
        end)
        count.value = 5
        local rows = s:rows()
        assert.equal("input", trimmed(rows[2]))
        assert.equal("n5", trimmed(rows[3]))
    end)

    it("keeps the items declared inside a nested host for that host", function()
        local s = screen.new(20, 4)
        local rows = s:show(function()
            return bars(ito.ToolbarHost(ito.VStack({
                ito.Text("inner"):toolbar({ ito.ToolbarItem(placement.bottom_bar, text("mine")) }),
                ito.ToolbarItems(placement.bottom_bar),
            })))
        end)
        assert.equal("inner", trimmed(rows[1]))
        assert.equal("mine", trimmed(rows[2]))
        assert.equal("input", trimmed(rows[4]))
        assert.same({}, reported)
    end)

    it("reports an item that raises once, and still draws the others", function()
        local s = screen.new(20, 3)
        local function show()
            return s:show(function()
                return bars(ito.Text("body")):toolbar({
                    ito.ToolbarItem(placement.bottom_bar, function()
                        error("no badge today", 0)
                    end),
                    ito.ToolbarItem(placement.bottom_bar, text("fine")),
                })
            end)
        end
        local rows = show()
        s:rows()
        assert.equal("fine", trimmed(rows[3]))
        assert.same({ "toolbar item: no badge today" }, reported)
    end)

    it("says once when nothing shows the items placed somewhere", function()
        local s = screen.new(20, 2)
        local function show()
            return s:show(function()
                return ito.ToolbarHost(ito.Text("body")):toolbar({ ito.ToolbarItem(placement.bottom_bar, text("lost")) })
            end)
        end
        show()
        s:rows()
        assert.same({ "toolbar: nothing shows the items placed at bottom_bar" }, reported)
    end)

    it("refuses placements and contents that are not toolbar values", function()
        assert.has_error(function()
            ito.ToolbarItem("bottom", text("x"))
        end, "ToolbarItem takes one of ito.ToolbarPlacement first")
        assert.has_error(function()
            ito.ToolbarItem(placement.bottom_bar, ito.Text("x"))
        end, "ToolbarItem takes a view, or a function that returns one, second")
        assert.has_error(function()
            ito.Text("x"):toolbar("x")
        end, "toolbar takes a list of ito.ToolbarItem")
    end)
end)
