local ito = require("ito")
local screen = require("support.screen")

it("keeps the complete link on each wrapped fragment without changing text", function()
    local s = screen.new(12, 5)
    local url = "https://example.test/authorize?client_id=client&state=long-state"
    local rows = s:show(function()
        return ito.Text({ { "Open " }, { url, link = url } }):wrap():grow()
    end)
    local joined = ""
    for row = 0, 4 do
        assert.is_nil(rows[row + 1]:find("\27", 1, true))
        for _, run in ipairs(s.screen:spans(row)) do
            if run.link then
                assert.equal(url, run.link)
                joined = joined .. run.text
            end
        end
    end
    assert.equal(url:sub(1, #joined), joined)
    assert.is_true(#joined > 24)
end)

it("preserves links over explicit newlines and style merging", function()
    local s = screen.new(10, 3)
    s:show(function()
        return ito.Text({ { "one\ntwo", link = "https://example.test" } }):bold()
    end)
    for row = 0, 1 do
        local run = s.screen:spans(row)[1]
        assert.equal("https://example.test", run.link)
        assert.same({ "bold" }, run.modifiers)
    end
end)

it("redraws a changed link and removes it when plain text replaces it", function()
    local s = screen.new(10, 1)
    s.screen:line(0, 0, { { "same", link = "https://one.test" } })
    s.screen:flush()
    s.screen:line(0, 0, { { "same", link = "https://two.test" } })
    assert.equal("https://two.test", s.screen:spans(0)[1].link)
    s.screen:flush()
    s.screen:line(0, 0, "same")
    assert.is_nil(s.screen:spans(0)[1].link)
    assert.equal("same      ", s.screen:text(0))
end)

it("rejects control characters in hyperlink destinations", function()
    local s = screen.new(10, 1)
    for _, url in ipairs({ "", "https://x.test\27]52;c;data\7", "https://x.test\n" }) do
        assert.has_error(function()
            s.screen:line(0, 0, { { "click", link = url } })
        end)
    end
end)

it("keeps wide glyphs and clipping aligned", function()
    local s = screen.new(6, 1)
    s.screen:line(0, 0, { { "界abc", link = "https://example.test" } }, 3)
    s.screen:line(0, 3, "XYZ")
    assert.equal("界 aXYZ", s.screen:text(0))
    assert.equal("界", s.screen:spans(0)[1].text)
    s.screen:line(0, 0, "abcdef")
    assert.equal("abcdef", s.screen:text(0))
    for _, run in ipairs(s.screen:spans(0)) do
        assert.is_nil(run.link)
    end
end)
