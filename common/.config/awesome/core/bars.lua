local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local create_tags = require("core.tags").create_tags
local widgets = require("ben.widgets")

local logout_menu_widget = require("awesome-wm-widgets.logout-menu-widget.logout-menu")
local battery_widget = require("awesome-wm-widgets.battery-widget.battery")
local cpu_widget = require("awesome-wm-widgets.cpu-widget.cpu-widget")
local ram_widget = require("awesome-wm-widgets.ram-widget.ram-widget")
local spotify_widget = require("awesome-wm-widgets.spotify-widget.spotify")
local fs_widget = require("awesome-wm-widgets.fs-widget.fs-widget")
local weather_widget = require("awesome-wm-widgets.weather-widget.weather")

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
        expand = "none",
        {
            layout = wibox.layout.fixed.horizontal,
            screen.taglist,
        },
        {
            layout = wibox.layout.fixed.horizontal,
            {
                layout = wibox.layout.fixed.horizontal,
                spotify_widget({
                    font = Ben.fonts.normal,
                    play_icon = '/usr/share/icons/Papirus-Light/24x24/categories/spotify.svg',
                    pause_icon = '/usr/share/icons/Papirus-Dark/24x24/panel/spotify-indicator.svg',
                    dim_when_paused = true,
                    dim_opacity = 0.5,
                    max_length = -1,
                    show_tooltip = true,
                }),
            },
        },
        {
            layout = wibox.layout.fixed.horizontal,
            {
                layout = wibox.container.margin,
                left = 20,
                widgets.systray,
            },
            {
                layout = wibox.container.margin,
                left = 20,
                fs_widget()
            },
            {
                layout = wibox.container.margin,
                left = 20,
                battery_widget({
                    font = Ben.fonts.normal,
                    show_current_level = true,
                    display_notification = true,
                    charging_color = Ben.colors.green,
                    low_level_color = Ben.colors.red,
                    medium_level_color = Ben.colors.yellow,
                    show_notification_mode = "on_click",
                    notification_position = "top_right",
                    warning_msg_title = "Battery is dying",
                    size = 25,
                }),
            },
            {
                layout = wibox.container.margin,
                left = 20,
                cpu_widget(),
            },
            {
                layout = wibox.container.margin,
                left = 20,
                ram_widget({
                    widget_height = 50,
                    widget_width = 30,
                    color_used = Ben.colors.red,
                    color_free = Ben.colors.green,
                    widget_show_buf = false,
                }),
            },
            {
                layout = wibox.container.margin,
                widgets.clock,
            },
            {
                layout = wibox.container.margin,
                logout_menu_widget({
                    onlock = function() awful.spawn.with_shell('i3exit lock') end,
                    onsuspend = function() 
                        awful.spawn.with_shell('i3exit suspend')
                    end
                }),
            }
        },
    })
end)
