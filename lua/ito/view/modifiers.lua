local alignment = require("ito.view.alignment")
local Item = require("ito.toolbar.item")
local runtime = require("ito.runtime")
local color = require("ito.style.color")
local text_style = require("ito.style.text_style")

local TextStyle = text_style.TextStyle

local function whole(value, what)
    if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
        error(what .. " must be a whole number of cells, not " .. tostring(value), 3)
    end
    return value
end

local EDGES = { "top_left", "top_right", "bottom_left", "bottom_right", "horizontal", "vertical" }
local SIDES = { "top", "bottom", "leading", "trailing" }

return function(View)
    function View:padding(amount)
        self.inset = nil
        local sides = (self.fill ~= nil or self.edge ~= nil) and "margin" or "pad"
        if type(amount) == "table" then
            if amount.vertical ~= nil then
                local cells = whole(amount.vertical, "vertical padding")
                self[sides .. "_top"], self[sides .. "_bottom"] = cells, cells
            end
            if amount.horizontal ~= nil then
                local cells = whole(amount.horizontal, "horizontal padding")
                self[sides .. "_leading"], self[sides .. "_trailing"] = cells, cells
            end
            for _, side in ipairs(SIDES) do
                if amount[side] ~= nil then
                    self[sides .. "_" .. side] = whole(amount[side], side .. " padding")
                end
            end
        else
            local cells = whole(amount, "padding")
            for _, side in ipairs(SIDES) do
                self[sides .. "_" .. side] = cells
            end
        end
        return self
    end

    function View:border(set, opts)
        if type(set) ~= "table" then
            error("a border needs one of the theme's borders, not " .. tostring(set), 2)
        end
        for _, edge in ipairs(EDGES) do
            if type(set[edge]) ~= "string" then
                error("a border needs " .. edge, 2)
            end
        end
        opts = opts or {}
        local edges = opts.edges or View.Edges.all
        if edges ~= View.Edges.all and edges ~= View.Edges.horizontal then
            error("a border's edges are Edges.all or Edges.horizontal", 2)
        end
        self.edge, self.edges = set, edges
        self.inset = nil
        self.border_style = opts.color ~= nil and TextStyle({ foreground = color.check(opts.color, "a border's color") }) or nil
        return self
    end

    function View:background(value)
        if text_style.is(value) then
            self.fill = value
        elseif color.is(value) then
            self.fill = TextStyle({ background = value })
        else
            error("background must be an ito.Color or an ito.TextStyle, not a " .. type(value), 2)
        end
        return self
    end

    function View:opaque()
        self.opaque_fill = true
        return self
    end

    function View:hidden(hide)
        self.is_hidden = hide ~= false
        return self
    end

    function View:focus_scope(value)
        if value == nil then
            error("focus_scope needs a value", 2)
        end
        self.scoped = value
        return self
    end

    function View:title(title)
        self.heading = title
        return self
    end

    function View:shrink()
        self.shrinks = true
        return self
    end

    function View:grow(weight)
        weight = weight or 1
        if type(weight) ~= "number" or weight <= 0 then
            error("grow takes a weight above 0, not " .. tostring(weight), 2)
        end
        self.weight = weight
        return self
    end

    function View:height(cells)
        self.fixed_height = whole(cells, "height")
        return self
    end

    function View:width(cells)
        self.fixed_width = whole(cells, "width")
        return self
    end

    function View:max_height(cells)
        self.most_height = cells == math.huge and cells or whole(cells, "max_height")
        return self
    end

    function View:share(fraction)
        if type(fraction) ~= "number" or fraction < 0 or fraction > 1 then
            error("share takes a fraction from 0 to 1, not " .. tostring(fraction), 2)
        end
        self.fraction = fraction
        return self
    end

    function View:align(value)
        if not alignment.is(value) then
            error("align takes one of ito.Alignment", 2)
        end
        self.aligned = value
        return self
    end

    function View:overlay(content, placement)
        self.overlays = self.overlays or {}
        self.overlays[#self.overlays + 1] = { content = content, alignment = alignment.of(placement, "overlay") }
        return self
    end

    function View:layout_id(tag)
        if tag == nil then
            error("layout_id needs a value", 2)
        end
        self.tag = tag
        return self
    end

    function View:preference(key, value)
        if not runtime.is_preference(key) then
            error("preference takes an ito.PreferenceKey", 2)
        end
        self.reported = self.reported or {}
        self.reported[#self.reported + 1] = { key = key, value = value }
        return self
    end

    function View:overlay_preference_value(key, build, placement)
        if not runtime.is_preference(key) then
            error("overlay_preference_value takes an ito.PreferenceKey", 2)
        end
        if type(build) ~= "function" then
            error("overlay_preference_value needs a function that builds a view", 2)
        end
        self.readers = self.readers or {}
        self.readers[#self.readers + 1] = { key = key, build = build, alignment = alignment.of(placement, "overlay_preference_value") }
        return self
    end

    function View:toolbar(items)
        if type(items) ~= "table" or runtime.is_view(items) then
            error("toolbar takes a list of ito.ToolbarItem", 2)
        end
        for _, item in ipairs(items) do
            if item and not Item.is(item) then
                error("toolbar takes a list of ito.ToolbarItem", 2)
            end
        end
        self.declared = self.declared or {}
        self.declared[#self.declared + 1] = items
        return self
    end

    function View:id(...)
        self.key = runtime.identity(...)
        return self
    end

    function View:on_tap(handler)
        if type(handler) ~= "function" then
            error("on_tap takes a function", 2)
        end
        self.click = handler
        return self
    end
end
