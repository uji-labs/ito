local native = require("ito.image.native")

local function choices(names)
    local values = {}
    for _, name in ipairs(names) do
        values[name] = { name = name }
    end
    return values
end

return {
    ImageSource = { file = native.file, bytes = native.bytes, rgba = native.rgba },
    ImageMode = choices({ "fit", "fill", "stretch", "original" }),
    ImageSampling = choices({ "nearest", "linear" }),
    ImageWheel = choices({ "pass", "zoom", "pan" }),
}
