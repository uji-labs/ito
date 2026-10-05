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
            built = {}
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

    it("spins while it is shown and asks for the next frame", function()
        local s = screen.new(30, 2)
        local rows = s:show(function()
            return kit.VStack({ kit.Spinner() })
        end)
        assert.is_true(rows[1]:find("^[-+]") ~= nil)
        assert.equal(0.1, s.frame.wake)
    end)
end)
