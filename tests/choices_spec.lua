local screen = require("support.screen")

describe("the choices control", function()
    local kit = require("ito")
    local trimmed = screen.trimmed

    local function choices(s, items, handlers)
        handlers = handlers or {}
        return s:show(function()
            local control = kit.Choices(items)
            if handlers.on_choose then
                control:on_choose(handlers.on_choose)
            end
            if handlers.on_other then
                control:on_other(handlers.on_other)
            end
            return control
        end)
    end

    it("numbers the choices, sets each description under its label, and writes the last answer", function()
        local rows = screen.new(60, 6):show(function()
            return kit.Choices({
                { label = "Postgres", description = "Mature and relational" },
                { label = "SQLite", description = "One file, no server" },
            })
        end)
        assert.equal("❯ 1. Postgres", trimmed(rows[1]))
        assert.equal("     Mature and relational", trimmed(rows[2]))
        assert.equal("  2. SQLite", trimmed(rows[3]))
        assert.equal("     One file, no server", trimmed(rows[4]))
        assert.equal("  3. Type something.", trimmed(rows[5]))
        assert.equal("Enter to select · Tab/Arrow keys to navigate · Esc to cancel", trimmed(rows[6]))
    end)

    it("moves with the arrows and with tab, and answers with the choice that is focused", function()
        local s = screen.new(30, 4)
        local answered
        local rows = choices(s, { { label = "one" }, { label = "two" } }, {
            on_choose = function(item, index)
                answered = { item.label, index }
            end,
        })
        assert.equal("❯ 1. one", trimmed(rows[1]))
        rows = s:press("down")
        assert.equal("❯ 2. two", trimmed(rows[2]))
        rows = s:press("tab")
        assert.equal("❯ 3. █Type something.", trimmed(rows[3]))
        rows = s:press("backtab")
        assert.equal("❯ 2. two", trimmed(rows[2]))
        s:press("enter")
        assert.same({ "two", 2 }, answered)
    end)

    it("types an answer on the last row and hands it over when enter is pressed", function()
        local s = screen.new(30, 4)
        local wrote, answered
        choices(s, { { label = "one" } }, {
            on_choose = function(item)
                answered = item.label
            end,
            on_other = function(text)
                wrote = text
            end,
        })
        local rows = s:press("down")
        assert.equal("❯ 2. █Type something.", trimmed(rows[2]))
        rows = s:press("y", "e", "s")
        assert.equal("❯ 2. yes█", trimmed(rows[2]))
        rows = s:press("backspace")
        assert.equal("❯ 2. ye█", trimmed(rows[2]))
        s:press("enter")
        assert.equal("ye", wrote)
        assert.is_nil(answered)
    end)

    it("keeps an answer that is only spaces from being written", function()
        local s = screen.new(30, 4)
        local wrote = false
        choices(s, { { label = "one" } }, {
            on_other = function()
                wrote = true
            end,
        })
        s:press("down", " ", "enter")
        assert.is_false(wrote)
    end)

    it("keeps the answer that was typed while the cursor moves over the choices", function()
        local s = screen.new(30, 4)
        choices(s, { { label = "one" }, { label = "two" } })
        local rows = s:press("down", "down", "h", "i", "up")
        assert.equal("❯ 2. two", trimmed(rows[2]))
        assert.equal("  3. hi", trimmed(rows[3]))
        rows = s:press("down")
        assert.equal("❯ 3. hi█", trimmed(rows[3]))
        rows = s:press("backspace", "backspace")
        assert.equal("❯ 3. █Type something.", trimmed(rows[3]))
    end)

    it("wraps a description in the room left under its label", function()
        local rows = screen.new(20, 6):show(function()
            return kit.Choices({ { label = "one", description = "a description that goes past the room" } })
        end)
        assert.equal("❯ 1. one", trimmed(rows[1]))
        assert.equal("     a description", trimmed(rows[2]))
        assert.equal("     that goes past", trimmed(rows[3]))
        assert.equal("     the room", trimmed(rows[4]))
    end)

    it("keeps the hint under the choices while they are scrolled", function()
        local s = screen.new(60, 6)
        local items = {}
        for index = 1, 8 do
            items[index] = { label = "choice " .. index }
        end
        local rows = choices(s, items)
        assert.equal("❯ 1. choice 1", trimmed(rows[1]))
        assert.equal("  5. choice 5", trimmed(rows[5]))
        assert.equal("Enter to select · Tab/Arrow keys to navigate · Esc to cancel", trimmed(rows[6]))
        rows = s:press("down", "down", "down", "down", "down")
        assert.equal("❯ 6. choice 6", trimmed(rows[5]))
        assert.equal("Enter to select · Tab/Arrow keys to navigate · Esc to cancel", trimmed(rows[6]))
    end)

    it("takes the tab of a choice past the last one", function()
        local s = screen.new(30, 4)
        choices(s, { { label = "one" } })
        local rows = s:press("tab")
        assert.equal("❯ 2. █Type something.", trimmed(rows[2]))
        rows = s:press("tab")
        assert.equal("❯ 2. █Type something.", trimmed(rows[2]))
    end)
    it("asks its stack for the room its descriptions need", function()
        local rows = screen.new(64, 6):show(function()
            return kit.VStack({
                kit.Choices({ { label = "one", description = "the first one" } }),
                kit.Text("end"),
            })
        end)
        assert.same({
            "❯ 1. one",
            "     the first one",
            "  2. Type something.",
            "Enter to select · Tab/Arrow keys to navigate · Esc to cancel",
            "end",
        }, {
            trimmed(rows[1]),
            trimmed(rows[2]),
            trimmed(rows[3]),
            trimmed(rows[4]),
            trimmed(rows[5]),
        })
    end)

    it("keeps a choice without a description on one row", function()
        local rows = screen.new(30, 5):show(function()
            return kit.Choices({ { label = "one" }, { label = "two", description = "the second one" } })
        end)
        assert.equal("❯ 1. one", trimmed(rows[1]))
        assert.equal("  2. two", trimmed(rows[2]))
        assert.equal("     the second one", trimmed(rows[3]))
        assert.equal("  3. Type something.", trimmed(rows[4]))
    end)

    it("refuses anything but choices with labels", function()
        local s = screen.new(30, 3)
        assert.has_error(function()
            s:show(function()
                return kit.Choices("one")
            end)
        end, "Choices takes a list of choices, not a string")
        assert.error_matches(function()
            s:show(function()
                return kit.Choices({ { description = "no label" } })
            end)
        end, "not table: 0x", 1, true)
        assert.has_error(function()
            s:show(function()
                return kit.Choices({ { label = "one", description = 2 } })
            end)
        end, "Choices takes a description that is a string, not a number")
    end)
end)
