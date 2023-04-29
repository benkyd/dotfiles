local awful = require("awful")
local wibox = require("wibox")

local wallpapers = {
 "/home/benk/pictures/Wallpapers/waves_right_colored.png",
}

for screen, wallpaper in ipairs(wallpapers) do
  awful.wallpaper({
    screen = screen,
    widget = {
      widget = wibox.container.tile,
      {
        widget = wibox.widget.imagebox,
        image = wallpaper,
      },
    },
  })
end
