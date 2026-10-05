local ito = require("ito")
local class = require("ito.class")

local Group = class(ito.Primitive)

local function counter(captured)
    return ito.view(function(props)
        local count = ito.state(props.start or 0)
        captured[props.name or #captured + 1] = count
        return Group({})
    end)
end

local function composition()
    local asked = { count = 0 }
    local composed = ito.Composition(function()
        asked.count = asked.count + 1
    end)
    return composed, asked
end

describe("composition", function()
    it("keeps a view's state while it stays in the same place", function()
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        local App = ito.view(function()
            return Group({ Counter({ name = "a" }), Counter({ name = "b", start = 5 }) })
        end)
        composed:compose(App())
        local first = states.a
        states.a.value = 3
        composed:compose(App())
        assert.equal(first, states.a)
        assert.equal(3, states.a.value)
        assert.equal(5, states.b.value)
    end)

    it("asks for a new frame only when a state really changes", function()
        local states = {}
        local Counter = counter(states)
        local composed, asked = composition()
        composed:compose(Group({ Counter({ name = "a" }) }))
        local before = asked.count
        states.a.value = 0
        assert.equal(before, asked.count)
        states.a.value = 1
        assert.equal(before + 1, asked.count)
        assert.is_true(composed.dirty)
        composed:compose(Group({ Counter({ name = "a" }) }))
        assert.is_false(composed.dirty)
    end)

    it("asks every view that read a state made outside a view for a new frame", function()
        local shared = ito.state("one")
        local Reader = ito.view(function()
            return ito.Text(shared.value)
        end)
        local first, asked_first = composition()
        local second, asked_second = composition()
        local idle, asked_idle = composition()
        first:compose(Reader())
        second:compose(Reader())
        idle:compose(ito.Text("other"))
        shared.value = "two"
        assert.equal(1, asked_first.count)
        assert.equal(1, asked_second.count)
        assert.equal(0, asked_idle.count)
    end)

    it("moves keyed state with its item when the list is reordered", function()
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        local function list(order)
            local children = {}
            for index, name in ipairs(order) do
                children[index] = Counter({ name = name }):id(name)
            end
            return Group(children)
        end
        composed:compose(list({ "x", "y", "z" }))
        states.x.value, states.z.value = 10, 30
        composed:compose(list({ "z", "y", "x" }))
        assert.equal(10, states.x.value)
        assert.equal(30, states.z.value)
        assert.equal(0, states.y.value)
    end)

    it("starts a view fresh when its id changes", function()
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        composed:compose(Group({ Counter({ name = "form" }):id(1) }))
        states.form.value = 8
        composed:compose(Group({ Counter({ name = "form" }):id(1) }))
        assert.equal(8, states.form.value)
        composed:compose(Group({ Counter({ name = "form" }):id(2) }))
        assert.equal(0, states.form.value)
    end)

    it("matches an id made of several values by value", function()
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        local function pairs_of(order)
            local children = {}
            for index, pair in ipairs(order) do
                children[index] = Counter({ name = pair[1] .. pair[2] }):id(pair[1], pair[2])
            end
            return Group(children)
        end
        composed:compose(pairs_of({ { "a", 1 }, { "a", 2 } }))
        states.a1.value, states.a2.value = 1, 2
        composed:compose(pairs_of({ { "a", 2 }, { "a", 1 } }))
        assert.equal(1, states.a1.value)
        assert.equal(2, states.a2.value)
        composed:compose(pairs_of({ { "a", 2 } }))
        composed:compose(pairs_of({ { "a", 2 }, { "a", 1 } }))
        assert.equal(0, states.a1.value)
    end)

    it("refuses two siblings with one id, and ids that are not values", function()
        local Counter = counter({})
        local composed = composition()
        assert.has_error(function()
            composed:compose(Group({ Counter():id("x"), Counter():id("x") }))
        end, "two views in one container have the id x")
        assert.has_error(function()
            composed:compose(Group({ Counter():id("x", 1), Counter():id("x", 1) }))
        end, "two views in one container have the id (x, 1)")
        assert.has_error(function()
            Counter():id(nil)
        end)
        composed:compose(Group({ Group({ Counter():id("x") }), Group({ Counter():id("x") }) }))
    end)

    it("applies a view's modifiers to what its body returns before it is placed", function()
        local Label = ito.view(function()
            return ito.Text("x")
        end)
        local composed = composition()
        local root = composed:compose(Group({ Label():grow(3):id("label") }))
        assert.equal(3, root.composed[1].weight)
    end)

    it("starts fresh when a different view takes a place, or a view leaves", function()
        local states = {}
        local Counter = counter(states)
        local Other = counter(states)
        local composed = composition()
        composed:compose(Group({ Counter({ name = "a" }) }))
        states.a.value = 7
        composed:compose(Group({ Other({ name = "a" }) }))
        assert.equal(0, states.a.value)
        states.a.value = 4
        composed:compose(Group({ false }))
        composed:compose(Group({ Other({ name = "a" }) }))
        assert.equal(0, states.a.value)
    end)

    it("keeps places stable when a child is left out with false", function()
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        local function screen(show)
            return Group({ show and Counter({ name = "first" }), Counter({ name = "second" }) })
        end
        composed:compose(screen(true))
        states.second.value = 9
        composed:compose(screen(false))
        assert.equal(9, states.second.value)
    end)

    it("hands environment values down and lets a subtree override them", function()
        local Theme = ito.Local("plain")
        local seen = {}
        local Probe = ito.view(function(props)
            seen[props.name] = Theme.current
            return Group({})
        end)
        local composed = composition()
        composed:compose(Group({
            Probe({ name = "outside" }),
            Theme:provide(
                "dark",
                Group({
                    Probe({ name = "inside" }),
                    Theme:provide("light", Probe({ name = "deeper" })),
                })
            ),
        }))
        assert.same({ outside = "plain", inside = "dark", deeper = "light" }, seen)
        assert.equal("plain", Theme.current)
    end)

    it("explains a view used wrongly", function()
        assert.has_error(function()
            ito.remember(os.time)
        end, "ito.remember works only inside a view while it is composed")
        assert.has_error(function()
            ito.view("not a function")
        end, "ito.view needs a function that returns a view")
        local Broken = ito.view(function()
            return "text"
        end)
        assert.has_error(function()
            composition():compose(Broken())
        end, "a view must give a view, not a string")
        local states = {}
        local Counter = counter(states)
        local composed = composition()
        composed:compose(Counter({ name = "a" }))
        assert.has_error(function()
            states.a.other = 1
        end, "a state only has a value")
    end)
end)
