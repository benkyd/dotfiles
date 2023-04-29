local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")

local wallpapers = {
 "/home/benk/pictures/Wallpapers/waves_right_colored.png",
}
beautiful.wallpaper = wallpapers[1]

screen.connect_signal('request::wallpaper', function(s)
    awful.wallpaper {
        screen = s,
        widget = {
            image                 = beautiful.wallpaper,
            upscale               = true,
            downscale             = true,
            horizontal_fit_policy = "fit",
            vertical_fit_policy   = "fit",
            widget                = wibox.widget.imagebox
        }
    }
end)
