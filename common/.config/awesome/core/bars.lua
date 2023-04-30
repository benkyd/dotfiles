local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local create_tags = require("core.tags").create_tags
local widgets = require("ben.widgets")

local batteryarc_widget = require("awesome-wm-widgets.batteryarc-widget.batteryarc")

awful.screen.connect_for_each_screen(function(screen)
    local tags = create_tags(screen)

    screen.taglist = awful.widget.taglist({
        screen = screen,
        filter = awful.widget.taglist.filter.all,
        buttons = gears.table.join(
            awful.button({}, 1, function(tag)
                tag:view_only()
            end)
        ),
    })

    screen.wibar = awful.wibar({
        screen = screen,
        position = "bottom",
    })

    screen.wibar:setup({
        layout = wibox.layout.align.horizontal,
        {
            layout = wibox.layout.fixed.horizontal,
            screen.taglist,
        },
        widgets.separator,
        {
            layout = wibox.layout.fixed.horizontal,
            widgets.systray,
            batteryarc_widget({
                font = Ben.fonts.normal,
                show_current_level = true,
                charging_color = Ben.colors.green,
                low_level_color = Ben.colors.red,
                medium_level_color = Ben.colors.yellow,
                notification_position = "bottom_right",
                warning_msg_title = "Battery is dying",
            }),
            widgets.clock,
            widgets.launcher,
        },
    })
end)
