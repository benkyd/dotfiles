local ruled = require("ruled")
local awful = require("awful")
local naughty = require("naughty")

ruled.notification.connect_signal("request::rules", function()
  ruled.notification.append_rule({
    rule = {},
    properties = {
      screen = awful.screen.preferred,
      implicit_timeout = 2,
    },
  })
end)

naughty.connect_signal("request::display", function(notification)
  naughty.layout.box({ notification = notification })
end)
