local class = require("ito.class")
local controls = require("ito.controls")
local Frame = require("ito.frame")
local host = require("ito.host")
local layout = require("ito.layout")
local Line = require("ito.line")
local runtime = require("ito.runtime")
local Styles = require("ito.styles")
local text = require("ito.text")
local Themes = require("ito.theme")
local tty = require("ito.tty")
local View = require("ito.view")
local views = require("ito.views")

local M = {}

for _, group in ipairs({ runtime, views, controls }) do
    for name, value in pairs(group) do
        M[name] = value
    end
end

M.class = class
M.text = text
M.layout = layout
M.Line = Line
M.Styles = Styles
M.Themes = Themes
M.Frame = Frame
M.View = View
M.Edges = View.Edges
M.Side = View.Side
M.setup = host.setup
M.open = tty.open

function M.theme()
    return runtime.Theme.current
end

function M.rgb(value)
    if type(value) ~= "number" or value < 0 or value > 0xffffff or value % 1 ~= 0 then
        error("ito.rgb takes a colour such as 0xd4d4d4", 2)
    end
    return string.format("#%06x", value)
end

return M
