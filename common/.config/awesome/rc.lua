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



