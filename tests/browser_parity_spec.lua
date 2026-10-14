local screen = require("support.screen")
local ito = require("ito")

describe("shared browser and terminal views", function()
    local function contains(rows, text)
        for _, row in ipairs(rows) do
            if row:find(text, 1, true) then
                return true
            end
        end
        return false
    end

    it("renders the exact browser examples through the terminal host", function()
        for _, name in ipairs({ "counter", "list", "settings", "shop" }) do
            local build = assert(loadfile("web/examples/" .. name .. ".lua"))()
            local s = screen.new(72, 50)
            local rows = s:show(build)
            assert.is_true(contains(rows, "╭"), name .. " should draw its shared border")
            assert.is_true(contains(rows, "╰"), name .. " should fit and finish its border")
        end
    end)

    it("activates the unchanged counter example through terminal mouse input", function()
        local build = assert(loadfile("web/examples/counter.lua"))()
        local s = screen.new(72, 40)
        local rows = s:show(build)
        assert.is_true(contains(rows, "4 of 8 pages"))
        for row, text in ipairs(rows) do
            local at = text:find("One more page", 1, true)
            if at then
                rows = s:tap(row - 1, ito.text.width(text:sub(1, at - 1)))
                break
            end
        end
        assert.is_true(contains(rows, "5 of 8 pages"))
    end)

    it("supports buttons and disabled actions with terminal keyboard and mouse", function()
        local n, blocked = 0, false
        local s = screen.new(30, 5)
        s:show(function()
            return ito.Button("Add", function()
                n = n + 1
            end):disabled(blocked)
        end)
        s:press("enter", " ")
        assert.equal(2, n)
        blocked = true
        s:show(function()
            return ito.Button("Add", function()
                n = n + 1
            end):disabled(blocked)
        end)
        s:press("enter")
        s:tap(0, 1)
        assert.equal(2, n)
    end)

    it("changes checkbox and slider state from terminal input", function()
        local checked, amount = ito.state(false), ito.state(5)
        local s = screen.new(40, 5)
        s:show(function()
            return ito.Checkbox("Done", checked)
        end)
        s:press(" ")
        assert.is_true(checked.value)
        s:tap(0, 0)
        assert.is_false(checked.value)
        s:show(function()
            return ito.Slider(amount, { min = 0, max = 10, step = 5 }):label("Amount")
        end)
        s:press("right", "right")
        assert.equal(10, amount.value)
        s:press("home")
        assert.equal(0, amount.value)
    end)

    it("labels a text field and submits the same value shown in the terminal", function()
        local value, submitted = ito.state(""), nil
        local s = screen.new(30, 5)
        s:show(function()
            return ito.TextField(value):label("Name"):on_submit(function(text)
                submitted = text
            end)
        end)
        local rows = s:press("h", "i", "enter")
        assert.equal("Name", screen.trimmed(rows[1]))
        assert.equal("hi", submitted)
        assert.equal("hi", value.value)
    end)
end)
