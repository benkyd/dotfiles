-- awesome_mode: api-level=4:screen=on
pcall(require, "luarocks.loader")
require("awful.autofocus")

local gears = require("gears")
local awful = require("awful")

-- Report potential errors
require("core.error_report")

-- Setup monitors
require("core.xrandr")

-- Initialize my own global namespace
require("ben")

-- Load keymaps
require("ben.keymaps")

-- layouts (tiling (in a tiling window manager))
require("core.layouts")

-- anime waifus
require("core.wallpapers")

-- theme (catppuccin (the best))
local beautiful = require("beautiful")
beautiful.init(os.getenv("HOME") .. "/.config/awesome/core/theme.lua")

-- bars
require("core.bars")

-- window rulez
require("core.rules")

-- noties
require("core.notifications")

-- autostart
require("ben.autostart")

-- my own components
require("ben.volume")
require("ben.backlight")

-- bling
local bling = require("plugins.bling")

-- fancy titlebars
local nice = require("plugins.nice")
nice({
    titlebar_color = Ben.colors.crust,
    titlebar_height = 20,
    titlebar_font = Ben.fonts.small,
    button_size = 14,
    mb_resize = nice.MB_MIDDLE,
    titlebar_radius = 0,
    mb_contextmenu = nice.MB_RIGHT,
    titlebar_items = {
        left = {},
        middle = "title",
        right = { "maximize", "close" },
    },
    maximize_color = Ben.colors.green,
    close_color = Ben.colors.red,
})

-- fix annoying fullscreen stuff
client.connect_signal("property::fullscreen", function(c)
    if c.fullscreen then
        c.border_width = c.fullscreen and 0 or beautiful.border_width
        c:geometry(c.screen.geometry)
        awful.titlebar.hide(c)
    else
        awful.titlebar.show(c)
    end
end)

