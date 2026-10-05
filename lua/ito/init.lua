local controls = require("ito.controls")
local Frame = require("ito.frame")
local host = require("ito.host")
local layout = require("ito.layout")
local Line = require("ito.line")
local runtime = require("ito.runtime")
local style = require("ito.style")
local text = require("ito.text")
local Themes = require("ito.theme")
local tty = require("ito.tty")
local toolbar = require("ito.toolbar")
local View = require("ito.view")
local views = require("ito.views")

local M = {}

for _, group in ipairs({ views, controls, toolbar, style }) do
    for name, value in pairs(group) do
        M[name] = value
    end
end

M.view = runtime.view
M.body = runtime.body
M.state = runtime.state
M.remember = runtime.remember
M.Local = runtime.Local
M.Theme = runtime.Theme
M.Composition = runtime.Composition
M.Primitive = runtime.Primitive
M.is_view = runtime.is_view
M.PreferenceKey = runtime.PreferenceKey
M.Subviews = runtime.Subviews

M.text = text
M.layout = layout
M.Line = Line
M.Themes = Themes
M.Frame = Frame
M.View = View
M.Edges = View.Edges
M.Alignment = View.Alignment
M.setup = host.setup
M.open = tty.open

function M.theme()
    return runtime.Theme.current
end

return M
