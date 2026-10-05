local call = require("ito.runtime.call")
local element = require("ito.runtime.element")
local environment = require("ito.runtime.environment")
local identity = require("ito.runtime.identity")
local preference = require("ito.runtime.preference")
local state = require("ito.runtime.state")
local subviews = require("ito.runtime.subviews")

return {
    identity = identity.identity,
    is_view = element.is_view,
    state = state.state,
    remember = state.remember,
    Local = environment.Local,
    Theme = environment.Theme,
    view = call.view,
    body = call.body,
    Build = call.Build,
    PreferenceKey = preference.PreferenceKey,
    is_preference = preference.is_preference,
    merged = preference.merged,
    Subviews = subviews.Subviews,
    Primitive = require("ito.runtime.primitive"),
    Composition = require("ito.runtime.composition"),
}
