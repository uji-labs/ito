local screen = require("support.screen")

describe("themes", function()
    local kit = require("ito")
    local THEME = screen.THEME

    local function with(changes)
        local theme = {}
        for group, value in pairs(THEME) do
            if type(value) == "table" then
                local copy = {}
                for key, item in pairs(value) do
                    copy[key] = item
                end
                value = copy
            end
            theme[group] = value
        end
        for group, value in pairs(changes) do
            if type(value) == "table" and type(theme[group]) == "table" then
                for key, item in pairs(value) do
                    theme[group][key] = item
                end
            else
                theme[group] = value
            end
        end
        return theme
    end

    local function themes(load)
        return kit.Themes({
            default = THEME,
            load = load or function(name)
                error("no theme named " .. name, 0)
            end,
        })
    end

    it("takes a theme whose colours and styles are values", function()
        local warm = with({ name = "warm", colors = { accent = kit.rgb(0xff8800) } })
        warm.styles.accent = kit.TextStyle({ foreground = warm.colors.accent, bold = true })
        local s = screen.new(10, 1)
        s.themes:select(warm)
        s:show(function()
            return kit.Spinner()
        end)
        assert.equal("#FF8800", s.screen:spans(0)[1].fg)
        assert.equal(kit.rgb(0xff8800), kit.theme().colors.accent)
    end)

    it("loads a theme by name, built by a function when the module gives one", function()
        local engine = themes(function(name)
            return function()
                return with({ name = name, colors = { muted = kit.Color.gray } })
            end
        end)
        engine:select("grey")
        assert.equal(kit.Color.gray, engine.tokens.colors.muted)
        assert.equal(kit.Color.gray, engine:context().colors.muted)
    end)

    it("names what is wrong with a theme", function()
        local engine = themes(function(name)
            return name == "number" and 42 or nil
        end)
        local cases = {
            { with({ roles = {} }), "theme.roles: a theme has name, colors, styles, symbols" },
            { with({ palette = {} }), "theme.palette: a theme has name" },
            { with({ extends = "default" }), "theme.extends: a theme has name" },
            { with({ colors = { text = "#d4d4d4" } }), "theme.colors.text: must be an ito.Color, not a string" },
            { with({ styles = { text = { fg = "text" } } }), "theme.styles.text: must be an ito.TextStyle, not a table" },
            { with({ symbols = { spiner = "x" } }), "theme.symbols.spiner: the default theme has no symbol named spiner" },
            { with({ limits = { spinner_interval = -1 } }), "theme.limits.spinner_interval: must be a number that is not negative" },
            { with({ styles = { cursor = false } }), "theme.styles.cursor: must be an ito.TextStyle, not a boolean" },
            { with({ templates = false }), "theme.templates: must be a table, not a boolean" },
            { "number", "theme number must return a theme or a function that builds one" },
        }
        local missing = with({})
        missing.styles.cursor = nil
        cases[#cases + 1] = { missing, "theme.styles.cursor: must be set, as every theme has it" }
        for _, case in ipairs(cases) do
            local ok, err = pcall(engine.select, engine, case[1])
            assert.is_false(ok, case[2])
            assert.truthy(tostring(err):find(case[2], 1, true), "expected " .. case[2] .. ", got " .. tostring(err))
        end
    end)

    it("lets a theme add colours and styles of its own, and raises for one it lacks", function()
        local engine = themes()
        local own = with({ colors = { link = kit.Color.blue } })
        own.styles.link = kit.TextStyle({ foreground = own.colors.link, underline = true })
        engine:select(own)
        local ctx = engine:context()
        assert.equal(kit.Color.blue, ctx.colors.link)
        assert.is_true(ctx.styles.link.underline)
        local ok, err = pcall(function()
            return ctx.styles.nope
        end)
        assert.is_false(ok)
        assert.truthy(err:find("the theme has no style named nope", 1, true))
        ok, err = pcall(function()
            return ctx.colors.nope
        end)
        assert.is_false(ok)
        assert.truthy(err:find("the theme has no color named nope", 1, true))
    end)
end)
