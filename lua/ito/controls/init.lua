local basic = require("ito.controls.basic")

local controls = {
    ImageViewer = require("ito.controls.image_viewer"),
    ImageViewport = require("ito.controls.image_viewport"),
    TextField = require("ito.controls.text_field"),
    Choices = require("ito.controls.choices"),
    List = require("ito.controls.list"),
    ScrollView = require("ito.controls.scroll_view"),
    ScrollState = require("ito.controls.scroll_state"),
    LazyVStack = require("ito.controls.lazy_vstack"),
    Spinner = require("ito.controls.spinner"),
}

for name, control in pairs(basic) do
    controls[name] = control
end
return controls
