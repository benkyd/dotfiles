local wibox = require("wibox")

local widgets = {}

widgets.clock = wibox.widget({
  widget = wibox.widget.textclock,
  format = "  %H:%M:%S %a %d/%m/%Y  ",
  refresh = 1,
})

widgets.separator = wibox.widget.separator()

widgets.systray = wibox.widget.systray()
widgets.systray:set_base_size(30)

return widgets
