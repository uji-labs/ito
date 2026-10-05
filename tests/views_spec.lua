local screen = require("support.screen")

describe("the view kit", function()
    local kit = require("ito")
    local trimmed = screen.trimmed

    it("styles text with modifiers", function()
        local s = screen.new(20, 4)
        s:show(function()
            return kit.VStack({ kit.Text("hi"):bold():foreground(kit.Color.indexed(214)):background(kit.rgb(0x102030)) })
        end)
        local run = s.screen:spans(0)[1]
        assert.equal("hi", run.text)
        assert.equal("214", run.fg)
        assert.equal("#102030", run.bg)
        assert.same({ "bold" }, run.modifiers)
    end)

    it("pads, borders and titles a view, and stacks with spacers", function()
        local s = screen.new(20, 8)
        local rows = s:show(function(ctx)
            return kit.VStack({
                kit.Text("top"):padding({ horizontal = 2 }),
                kit.Spacer(),
                kit.Text("in"):padding(1):border(ctx.borders.rounded, { color = kit.Color.indexed(196) }):title(" t "),
            })
        end)
        assert.equal("  top", trimmed(rows[1]))
        assert.equal("╭ t ───────────────╮", rows[4])
        assert.equal("│                  │", rows[5])
        assert.equal("│ in               │", rows[6])
        assert.equal("╰──────────────────╯", rows[8])
        assert.equal("196", s.screen:spans(3)[1].fg)
    end)

    it("builds lines for the width a view gets", function()
        local s = screen.new(12, 3)
        local widths = {}
        local rows = s:show(function()
            return kit.HStack({
                kit.Text("ab"),
                kit.Lines(function(width)
                    widths[#widths + 1] = width
                    return { { { string.rep("x", width) } }, { { tostring(width) } } }
                end),
            })
        end)
        assert.equal("abxxxxxxxxxx", rows[1])
        assert.equal("  10", screen.trimmed(rows[2]))
        assert.equal(10, widths[#widths])
        local built = 0
        local build = function(width)
            built = built + 1
            return { { { tostring(width) } } }
        end
        s:show(function()
            return kit.Lines(build)
        end)
        s:rows()
        s:rows()
        assert.equal(1, built)
    end)

    it("measures each child of a row at the width it gets", function()
        local s = screen.new(6, 4)
        local rows = s:show(function()
            return kit.VStack({
                kit.HStack({
                    kit.Text("> "),
                    kit.Lines(function(width)
                        local lines = {}
                        for index = 1, math.ceil(8 / width) do
                            lines[index] = { { string.rep("w", width) } }
                        end
                        return lines
                    end),
                }),
                kit.Text("end"),
            })
        end)
        assert.equal("> wwww", rows[1])
        assert.equal("  wwww", rows[2])
        assert.equal("end", trimmed(rows[3]))
    end)

    it("lays a row out by width, share and growth", function()
        local s = screen.new(20, 2)
        local rows = s:show(function()
            return kit.VStack({
                kit.HStack({ kit.Text("a"):width(4), kit.Text("b"):share(0.5), kit.Text("c"):grow() }),
            })
        end)
        assert.equal("a   b         c", trimmed(rows[1]))
    end)

    it("takes modifiers on a view of its own and layers views in a ZStack", function()
        local s = screen.new(20, 6)
        local Label = kit.view(function(props)
            return kit.Text(props.text)
        end)
        local rows = s:show(function(ctx)
            return kit.ZStack({
                Label({ text = "low" }):align(kit.Alignment.bottom_leading),
                Label({ text = "box" }):border(ctx.borders.plain):width(7):height(3),
            })
        end)
        assert.equal("low", trimmed(rows[6]))
        assert.equal("      ┌─────┐", rows[2]:gsub("%s+$", ""))
        assert.equal("      │box  │", rows[3]:gsub("%s+$", ""))
    end)

    it("keeps a view's state across frames and redraws when a tap changes it", function()
        local s = screen.new(20, 4)
        local Counter = kit.view(function()
            local count = kit.state(0)
            return kit.Text("taps " .. count.value):on_tap(function()
                count.value = count.value + 1
            end)
        end)
        local rows = s:show(function()
            return kit.VStack({ Counter() })
        end)
        assert.equal("taps 0", trimmed(rows[1]))
        s:tap(0, 2)
        assert.equal("taps 1", trimmed(s:rows()[1]))
        s:tap(0, 5)
        assert.equal("taps 2", trimmed(s:rows()[1]))
    end)
end)

describe("the view controls", function()
    local kit = require("ito")
    local trimmed = screen.trimmed

    it("edits the state a text field is bound to", function()
        local s = screen.new(30, 4)
        local query = { value = "" }
        local submitted
        local Search = kit.view(function()
            query = kit.state("")
            return kit.VStack({
                kit.TextField(query):placeholder("search"):on_submit(function(value)
                    submitted = value
                end),
                kit.Text("you typed " .. query.value),
            })
        end)
        local rows = s:show(function()
            return Search()
        end)
        assert.equal("█search", trimmed(rows[1]))
        rows = s:press("a", "b", "c", "left", "backspace")
        assert.equal("ac", query.value)
        assert.equal("a█c", trimmed(rows[1]))
        assert.equal("you typed ac", trimmed(rows[2]))
        s:press("enter")
        assert.equal("ac", submitted)
    end)

    it("masks a hidden text field", function()
        local s = screen.new(30, 2)
        local secret = { value = "key" }
        local rows = s:show(function()
            return kit.TextField(secret):hidden()
        end)
        assert.equal("•••█", trimmed(rows[1]))
    end)

    it("builds only the rows a list shows and moves through them with keys and the wheel", function()
        local s = screen.new(30, 5)
        local items, built, chosen = {}, {}, nil
        for index = 1, 100 do
            items[index] = "item " .. index
        end
        local rows = s:show(function()
            return kit.List(items, function(item, _, selected)
                built[#built + 1] = item
                return kit.Text((selected and "> " or "  ") .. item)
            end):on_choose(function(item)
                chosen = item
            end)
        end)
        assert.equal(5, #built)
        assert.equal("> item 1", trimmed(rows[1]))
        rows = s:press("down", "down")
        assert.equal("> item 3", trimmed(rows[3]))
        rows = s:press("pagedown", "pagedown")
        assert.equal("> item 13", trimmed(rows[5]))
        assert.equal("  item 9", trimmed(rows[1]))
        rows = s:press("end")
        assert.equal("> item 100", trimmed(rows[5]))
        s:press("enter")
        assert.equal("item 100", chosen)
        s:wheel(2, 2, -1)
        built = {}
        rows = s:rows()
        assert.equal("> item 97", trimmed(rows[2]))
        assert.is_true(#built <= 6)
    end)

    it("layers a ZStack's children and aligns each one, the child's own alignment first", function()
        local s = screen.new(20, 4)
        local rows = s:show(function()
            return kit.ZStack({
                alignment = kit.Alignment.bottom_trailing,
                kit.Text("back"):grow(),
                kit.Text("tl"):align(kit.Alignment.top_leading),
                kit.Text("br"),
            })
        end)
        assert.equal("tlck", trimmed(rows[1]))
        assert.equal(string.rep(" ", 18) .. "br", rows[4])
    end)

    it("gives an aligned child its own width across a stack", function()
        local s = screen.new(20, 2)
        local rows = s:show(function()
            return kit.VStack({ kit.Text("left"), kit.Text("right"):align(kit.Alignment.trailing) })
        end)
        assert.equal("left", trimmed(rows[1]))
        assert.equal(string.rep(" ", 15) .. "right", rows[2])
    end)

    it("draws an overlay in front of a view, on a view of your own too", function()
        local s = screen.new(20, 2)
        local count
        local Counter = kit.view(function()
            count = kit.state(0)
            return kit.Text("count " .. count.value)
        end)
        local rows = s:show(function()
            return kit.VStack({
                kit.Text("base text here"):overlay(kit.Text("ON"), kit.Alignment.trailing),
                Counter():overlay(kit.Text("!"), kit.Alignment.trailing),
            })
        end)
        assert.equal("base text here    ON", rows[1])
        assert.equal("count 0" .. string.rep(" ", 12) .. "!", rows[2])
        count.value = 4
        rows = s:rows()
        assert.equal("count 4" .. string.rep(" ", 12) .. "!", rows[2])
    end)

    it("lets an ancestor build from the values its children report", function()
        local s = screen.new(20, 3)
        local Count = kit.PreferenceKey({
            default = 0,
            reduce = function(value, next_value)
                return value + next_value
            end,
        })
        local rows = s:show(function()
            return kit.VStack({
                kit.Text("a"):preference(Count, 2),
                kit.VStack({ kit.Text("b"):preference(Count, 3) }),
            }):overlay_preference_value(Count, function(total)
                return kit.Text("total " .. total)
            end, kit.Alignment.bottom_trailing)
        end)
        assert.equal(string.rep(" ", 13) .. "total 5", rows[3])
        assert.has_error(function()
            kit.Text("x"):preference("count", 1)
        end, "preference takes an ito.PreferenceKey")
    end)

    it("hands a builder the subviews that drew something, with their hints", function()
        local s = screen.new(20, 2)
        local count
        local Empty = kit.view(function()
            return false
        end)
        local function joined(subviews)
            count = #subviews
            local row = {}
            for index, subview in ipairs(subviews) do
                if index > 1 and not subview.weight and not subviews[index - 1].weight then
                    row[#row + 1] = kit.Text("|")
                end
                row[#row + 1] = subview
            end
            return kit.HStack(row)
        end
        local rows = s:show(function()
            return kit.VStack({
                kit.Subviews({ kit.Text("a"), Empty(), kit.Text("b"), kit.Spacer(), kit.Text("c") }, joined):height(1),
            })
        end)
        assert.equal(4, count)
        assert.equal("a|b" .. string.rep(" ", 16) .. "c", rows[1])
        assert.has_error(function()
            s:show(function()
                return kit.Subviews({ kit.Text("a") }, function(subviews)
                    return kit.HStack({ subviews[1], subviews[1] })
                end)
            end)
        end, "a subview can be placed once")
    end)

    it("draws a changed view in place while the view around it stays the same", function()
        local s = screen.new(10, 2)
        local word = kit.state("a")
        local runs = 0
        local Word = kit.view(function()
            return kit.Text(word.value)
        end)
        local Panel = kit.view(function()
            runs = runs + 1
            return kit.VStack({ kit.Text("top"), Word() })
        end)
        s:show(function()
            return Panel()
        end)
        word.value = "changed"
        local rows = s:rows()
        assert.same({ "top", "changed" }, { trimmed(rows[1]), trimmed(rows[2]) })
        assert.equal(1, runs)
    end)

    it("lays a view out again only when its room changes", function()
        local s = screen.new(20, 3)
        local arranged = 0
        local Column = kit.Layout(function(children, room)
            return room.width,
                #children,
                function(x, y)
                    arranged = arranged + 1
                    for index, child in ipairs(children) do
                        local width, height = child:measure(room)
                        child:place(x, y + index - 1, width, height)
                    end
                end
        end)
        local Letters = kit.view(function()
            return Column({ kit.Text("a"), kit.Text("b") })
        end)
        local tick = kit.state(0)
        s:show(function()
            return kit.VStack({ kit.Text(tostring(tick.value)), Letters() })
        end)
        local first = arranged
        tick.value = 1
        local rows = s:rows()
        assert.equal(first, arranged)
        assert.same({ "1", "a", "b" }, { trimmed(rows[1]), trimmed(rows[2]), trimmed(rows[3]) })
    end)

    it("lets a custom layout place its children, and leaves out the ones it skips", function()
        local s = screen.new(20, 3)
        local Corners = kit.Layout(function(children, room)
            return room.width,
                room.height,
                function(x, y)
                    for _, child in ipairs(children) do
                        local width, height = child:measure(room)
                        if child.layout_id == "start" then
                            child:place(x, y, width, height)
                        elseif child.layout_id == "end" then
                            child:place(x + room.width - width, y + room.height - height, width, height)
                        end
                    end
                end
        end)
        local rows = s:show(function()
            return Corners({ kit.Text("s"):layout_id("start"), kit.Text("hidden"), kit.Text("e"):layout_id("end") })
        end)
        assert.equal("s", trimmed(rows[1]))
        assert.equal("", trimmed(rows[2]))
        assert.equal(string.rep(" ", 19) .. "e", rows[3])
    end)

    it("builds content for the room it is given and keeps its state", function()
        local s = screen.new(20, 3)
        local count, failure
        local Probe = kit.view(function(props)
            count = kit.state(0)
            return kit.Text(props.room.width .. "x" .. props.room.height .. " " .. count.value)
        end)
        local rows = s:show(function()
            return kit.VStack({
                kit.SubcomposeLayout(function(room)
                    return Probe({ room = room })
                end),
                kit.SubcomposeLayout(function()
                    error("no room today", 0)
                end, {
                    failed = function(problem)
                        failure = problem
                    end,
                }),
                kit.Spacer(),
            })
        end)
        assert.equal("20x1 0", trimmed(rows[1]))
        count.value = 2
        rows = s:rows()
        assert.equal("20x1 2", trimmed(rows[1]))
        assert.equal("no room today", failure)
    end)

    it("keeps a row's state and the chosen row with their items when the list changes", function()
        local s = screen.new(30, 4)
        local items = { { id = "a" }, { id = "b" }, { id = "c" } }
        local opened = {}
        local Row = kit.view(function(props)
            local open = kit.state(false)
            opened[props.item.id] = open
            return kit.Text((props.selected and "> " or "  ") .. props.item.id .. (open.value and " open" or ""))
        end)
        local function build()
            return kit.List(items, function(item, _, selected)
                return Row({ item = item, selected = selected })
            end)
                :item_id(function(item)
                    return item.id
                end)
                :focused()
        end
        s:show(build)
        local rows = s:press("down")
        assert.equal("> b", trimmed(rows[2]))
        local open_b = opened.b
        open_b.value = true
        table.insert(items, 1, { id = "z" })
        rows = s:rows()
        assert.equal("  a", trimmed(rows[1]))
        assert.equal("> b open", trimmed(rows[2]))
        rows = s:press("home")
        assert.equal("> z", trimmed(rows[1]))
        items[#items + 1] = { id = "b" }
        assert.has_error(function()
            s:rows()
        end, "two items in the list have the id b")
    end)

    it("scrolls a view taller than its room and can follow its end", function()
        local s = screen.new(20, 3)
        local function lines(count)
            local out = {}
            for index = 1, count do
                out[index] = "line " .. index
            end
            return table.concat(out, "\n")
        end
        local rows = s:show(function()
            return kit.ScrollView(kit.Text(lines(10)))
        end)
        assert.equal("line 1", trimmed(rows[1]))
        s:wheel(1, 1, 1)
        rows = s:rows()
        assert.equal("line 4", trimmed(rows[1]))
        rows = s:show(function()
            return kit.VStack({ kit.ScrollView(kit.Text(lines(10))):follow_end() })
        end)
        assert.equal("line 10", trimmed(rows[3]))
    end)

    it("shows the end of a lazy stack, keeps its place when scrolled up, and builds only what shows", function()
        local s = screen.new(10, 4)
        local items, built = {}, {}
        for index = 1, 20 do
            items[index] = { id = "m" .. index, rows = index % 3 == 0 and 2 or 1 }
        end
        local scroll = kit.ScrollState({ follow = true })
        local function rows()
            return s:show(function()
                return kit.LazyVStack(items, function(item)
                    built[item.id] = true
                    local lines = {}
                    for row = 1, item.rows do
                        lines[row] = { { item.id .. "." .. row } }
                    end
                    return kit.Lines(lines)
                end)
                    :item_id(function(item)
                        return item.id
                    end)
                    :state(scroll)
                    :footer(kit.Text("foot"))
            end)
        end
        local shown = rows()
        assert.same({ "m18.2", "m19.1", "m20.1", "foot" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]), trimmed(shown[4]) })
        assert.is_nil(built.m1)
        scroll:scroll(-2)
        shown = rows()
        assert.equal("m18.1", trimmed(shown[2]))
        assert.is_false(scroll.following)
        items[21] = { id = "m21", rows = 1 }
        shown = rows()
        assert.equal("m18.1", trimmed(shown[2]))
        scroll:to_top()
        shown = rows()
        assert.equal("m1.1", trimmed(shown[1]))
        scroll:to_end()
        shown = rows()
        assert.equal("m21.1", trimmed(shown[3]))
        assert.equal("foot", trimmed(shown[4]))
        assert.is_true(scroll.following)
    end)

    it("builds only the rows of a group that show, and scrolls through them", function()
        local s = screen.new(10, 3)
        local built = {}
        local scroll = kit.ScrollState({ follow = true })
        local Block = kit.view(function(props)
            built[props.name] = true
            return kit.Text(props.name)
        end)
        local items = { "short", "long" }
        local shown = s:show(function()
            return kit.LazyVStack(items, function(item)
                if item == "short" then
                    return kit.Text("short")
                end
                local blocks = {}
                for index = 1, 50 do
                    blocks[index] = Block({ name = "b" .. index })
                end
                return kit.Group(blocks)
            end):state(scroll)
        end)
        assert.same({ "b48", "b49", "b50" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]) })
        assert.is_nil(built.b1)
        scroll:to_top()
        shown = s:rows()
        assert.same({ "short", "b1", "b2" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]) })
    end)

    it("stays at the end of a lazy stack when scrolled down past it", function()
        local s = screen.new(10, 3)
        local items = {}
        for index = 1, 10 do
            items[index] = "row " .. index
        end
        local scroll = kit.ScrollState({ follow = true })
        s:show(function()
            return kit.LazyVStack(items, function(item)
                return kit.Text(item)
            end):state(scroll)
        end)
        scroll:scroll(5)
        local rows = s:rows()
        assert.same({ "row 8", "row 9", "row 10" }, { trimmed(rows[1]), trimmed(rows[2]), trimmed(rows[3]) })
        assert.is_true(scroll.following)
    end)

    it("leaves a lazy stack's rows alone while nothing they show changes", function()
        local s = screen.new(10, 3)
        local items = { "a", "b", "c" }
        local built, runs = 0, 0
        local Label = kit.view(function(props)
            runs = runs + 1
            return kit.Text(props.text)
        end)
        local shown = s:show(function()
            return kit.LazyVStack(items, function(item)
                built = built + 1
                return Label({ text = item })
            end)
        end)
        assert.same({ "a", "b", "c" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]) })
        local first_built, first_runs = built, runs
        shown = s:rows()
        assert.same({ "a", "b", "c" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]) })
        assert.equal(first_built, built)
        assert.equal(first_runs, runs)
    end)

    it("puts the footer right under content shorter than the room", function()
        local s = screen.new(10, 5)
        local shown = s:show(function()
            return kit.LazyVStack({ "a", "b" }, function(item)
                return kit.Text(item)
            end):footer(kit.Text("foot"))
        end)
        assert.same({ "a", "b", "foot", "" }, { trimmed(shown[1]), trimmed(shown[2]), trimmed(shown[3]), trimmed(shown[4]) })
    end)

    it("scrolls a view to the offset its scroll state holds", function()
        local s = screen.new(6, 2)
        local scroll = kit.ScrollState()
        local function rows()
            return s:show(function()
                return kit.ScrollView(kit.Lines({ { { "one" } }, { { "two" } }, { { "three" } } })):state(scroll)
            end)
        end
        assert.equal("one", trimmed(rows()[1]))
        scroll:scroll(1)
        assert.equal("two", trimmed(rows()[1]))
        scroll:scroll(5)
        assert.equal("two", trimmed(rows()[1]))
        assert.equal(1, scroll.offset)
    end)

    it("keeps a hidden view's state without drawing it, and clears under an opaque one", function()
        local s = screen.new(10, 3)
        local count
        local Counter = kit.view(function()
            count = kit.state(0)
            return kit.Text("n" .. count.value)
        end)
        local hide = kit.state(false)
        local shown = s:show(function()
            return kit.ZStack({
                alignment = kit.Alignment.top_leading,
                kit.Text("xxxxxxxx"),
                Counter():hidden(hide.value),
                kit.Text("ab"):width(4):opaque():hidden(not hide.value),
            })
        end)
        assert.equal("n0xxxxxx", trimmed(shown[1]))
        count.value = 3
        hide.value = true
        assert.equal("ab  xxxx", s:rows()[1]:sub(1, 8))
        hide.value = false
        assert.equal("n3xxxxxx", trimmed(s:rows()[1]))
    end)

    it("records the focus scope a control was drawn in", function()
        local s = screen.new(10, 2)
        local value = kit.state("")
        s:show(function()
            return kit.VStack({ kit.TextField(value):focus_scope("sheet") })
        end)
        assert.equal("sheet", s.frame.focusables[1].scope)
    end)

    it("spins while it is shown and asks for the next frame", function()
        local s = screen.new(30, 2)
        local rows = s:show(function()
            return kit.VStack({ kit.Spinner() })
        end)
        assert.is_true(rows[1]:find("^[-+]") ~= nil)
        assert.equal(0.1, s.frame.wake)
    end)
end)
