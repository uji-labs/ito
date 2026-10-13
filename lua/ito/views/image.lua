local class = require("ito.class")
local image = require("ito.image")
local native = require("ito.image_native")
local runtime = require("ito.runtime")
local Text = require("ito.views.text")
local View = require("ito.view")

local Image = class(View)
Image.live = true

local function number(value, low, high, name)
    if type(value) ~= "number" or value ~= value or value < low or value > high then
        error(name .. " must be a number between " .. low .. " and " .. high, 3)
    end
    return value
end

local function whole(value, low, name)
    number(value, low, 8192, name)
    if value % 1 ~= 0 then
        error(name .. " must be a whole number of pixels", 3)
    end
    return value
end

local function choice(value, values, name)
    for _, option in pairs(values) do
        if value == option then
            return value
        end
    end
    error(name .. " needs one of the image options", 3)
end

function Image:init(source)
    View.init(self, {})
    if not native.is_source(source) then
        error("Image takes an ito.ImageSource", 3)
    end
    self.source = source
    self.mode = image.ImageMode.fit
    self.anchor = View.Alignment.center
    self.filter = image.ImageSampling.linear
    self.turns, self.alpha = 0, 1
    self.description = "Image"
end

function Image:content_mode(mode)
    self.mode = choice(mode, image.ImageMode, "content_mode")
    return self
end

function Image:content_alignment(alignment)
    self.anchor = View.alignment_of(alignment, "content_alignment")
    return self
end

function Image:sampling(value)
    self.filter = choice(value, image.ImageSampling, "sampling")
    return self
end

function Image:crop(rect)
    if rect == nil then
        self.cropped = nil
    elseif type(rect) == "table" then
        self.cropped = {
            x = whole(rect.x, 0, "crop x"),
            y = whole(rect.y, 0, "crop y"),
            width = whole(rect.width, 1, "crop width"),
            height = whole(rect.height, 1, "crop height"),
        }
    else
        error("crop takes a rectangle in source pixels", 2)
    end
    return self
end

function Image:rotate(degrees)
    number(degrees, -360000, 360000, "rotation")
    if degrees % 90 ~= 0 then
        error("rotation must be a multiple of 90 degrees", 2)
    end
    self.turns = degrees % 360
    return self
end

function Image:opacity(value)
    self.alpha = number(value, 0, 1, "opacity")
    return self
end

function Image:alt(value)
    if type(value) ~= "string" then
        error("alt takes text describing the image", 2)
    end
    self.description = value
    return self
end

local function fallback(self, key, value)
    if type(value) ~= "function" and not runtime.is_view(value) then
        error(key .. " takes a view or a function returning a view", 3)
    end
    self[key] = value
    return self
end

function Image:placeholder(value)
    return fallback(self, "loading_view", value)
end

function Image:fallback(value)
    return fallback(self, "failed_view", value)
end

function Image:unsupported(value)
    return fallback(self, "unsupported_view", value)
end

function Image:compose(composition, node, environment)
    node.lazy = true
    self.memo, self.node = node.memo, node
    self.composition, self.environment = composition, environment
    return self
end

function Image:content_height(frame, width)
    local status = self.source:status()
    if status.phase ~= "ready" then
        return 1
    end
    local pixels = frame.screen:image_capabilities()
    local w, h = status.width, status.height
    if self.cropped then
        w, h = self.cropped.width, self.cropped.height
    end
    if self.turns % 180 ~= 0 then
        w, h = h, w
    end
    if self.mode == image.ImageMode.original then
        return math.ceil(h / pixels.cell_height)
    end
    return math.max(1, math.ceil(width * pixels.cell_width * h / (w * pixels.cell_height)))
end

function Image:options()
    return {
        mode = self.mode.name,
        sampling = self.filter.name,
        crop = self.cropped,
        rotation = self.turns,
        opacity = math.floor(self.alpha * 255 + 0.5),
        align_x = math.floor(self.anchor.x * 1000),
        align_y = math.floor(self.anchor.y * 1000),
    }
end

local Fallback = runtime.view(function(props)
    return props.build(props.status)
end)

function Image:draw_fallback(frame, phase, problem)
    local content
    if phase == "loading" then
        content = self.loading_view
    elseif phase == "unsupported" then
        content = self.unsupported_view or self.failed_view
    else
        content = self.failed_view
    end
    if not content then
        content = Text(self.description)
    elseif type(content) == "function" then
        content = Fallback({ build = content, status = { phase = phase, error = problem, source = self.source } })
    end
    local child = self.composition:place(content, self.node, "image fallback", self.environment)
    if child then
        child:place(frame, View.fit(frame, child, self.inner, self.anchor))
        local outer = frame:clip(self.inner)
        child:draw(frame)
        frame:unclip(outer)
    end
end

function Image:draw_content(frame)
    local inner = self.inner
    if not frame:shows(inner) then
        return
    end
    local clip = frame.clipping and frame.overlap(frame.clipping, inner) or inner
    local options = self:options()
    local phase, problem = frame.screen:image(self.source, inner, options, clip)
    local previous = self.memo.ready_image
    local kept = false
    if phase == "ready" then
        self.memo.ready_image = { source = self.source, width = inner.width, height = inner.height, options = options }
    elseif
        phase == "loading"
        and previous
        and previous.source == self.source
        and previous.width == inner.width
        and previous.height == inner.height
    then
        kept = frame.screen:image(self.source, inner, previous.options, clip, true) == "ready"
    end
    if phase ~= "ready" and not kept then
        self:draw_fallback(frame, phase, problem)
    end
    if phase == "loading" then
        frame:again(1 / 30)
    end
    self.node:sweep(self.composition.generation)
end

Image.number = number
Image.choice = choice

return Image
