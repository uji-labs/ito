describe("spans", function()
    local kit = require("ito")
    local red = kit.TextStyle({ foreground = kit.Color.red })
    local blue = kit.TextStyle({ foreground = kit.Color.blue })

    it("breaks a line at the last space that fits, drops that space and keeps each span's style", function()
        local rows = kit.spans.wrap({ { "print(", red }, { '"hello world"', blue }, { ")", red } }, 12)
        assert.same({
            { { "print(", red }, { '"hello', blue } },
            { { 'world"', blue }, { ")", red } },
        }, rows)
        rows = kit.spans.wrap({ { "one two three", red } }, 9)
        assert.same({ { { "one two", red } }, { { "three", red } } }, rows)
    end)

    it("keeps leading indentation with the text after it", function()
        local rows = kit.spans.wrap({ { "    return value", red } }, 12)
        assert.same({ { { "    return", red } }, { { "value", red } } }, rows)
    end)

    it("cuts a word longer than the width and splits a span across rows", function()
        local rows = kit.spans.wrap({ { "abcdefgh", red }, { "ij", blue } }, 4)
        assert.same({
            { { "abcd", red } },
            { { "efgh", red } },
            { { "ij", blue } },
        }, rows)
    end)

    it("keeps a style change inside a word on one row", function()
        local rows = kit.spans.wrap({ { "ab", red }, { "cd", blue }, { " ef", red } }, 5)
        assert.same({
            { { "ab", red }, { "cd", blue } },
            { { "ef", red } },
        }, rows)
    end)

    it("copies a line's on_click and a span's other fields to every row", function()
        local click = function() end
        local rows = kit.spans.wrap({ { "one two", red, extra = true }, on_click = click }, 4)
        assert.equal(2, #rows)
        for _, row in ipairs(rows) do
            assert.equal(click, row.on_click)
            assert.is_true(row[1].extra)
        end
    end)

    it("leaves a line alone when it fits, is empty or the width is zero", function()
        local short = { { "fits", red } }
        assert.same({ short }, kit.spans.wrap(short, 10))
        assert.same({ {} }, kit.spans.wrap({}, 10))
        assert.same({ short }, kit.spans.wrap(short, 0))
    end)

    it("counts wide text by characters like ito.text", function()
        local rows = kit.spans.wrap({ { "ééé ééé", red } }, 4)
        assert.same({ { { "ééé", red } }, { { "ééé", red } } }, rows)
    end)
end)
