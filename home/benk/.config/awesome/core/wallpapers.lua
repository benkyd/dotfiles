local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")

local wallpapers = {
 "/home/benk/pictures/Wallpapers/waves_right_colored.png",
 "/home/benk/pictures/Wallpapers/portal2.png",
}

Hostname = io.popen("uname -n"):read()

if Hostname == "ben-xps9310" then
    beautiful.wallpaper = wallpapers[2]
else
    beautiful.wallpaper = wallpapers[1]
end

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
