local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end


config.hide_tab_bar_if_only_one_tab = true
config.font = wezterm.font("Source Code Pro", { weight = "DemiBold" })
config.font_size = 10.0
config.line_height = 1.2

config.adjust_window_size_when_changing_font_size = false

config.color_scheme = 'Catppuccin Macchiato'

config.enable_wayland = true
config.window_background_opacity = 0.60
config.text_background_opacity = 0.80

config.macos_window_background_blur = 20
config.kde_window_background_blur = true

config.colors = {
    cursor_bg = '#c6a0f6',
    cursor_fg = 'black',
    cursor_border = '#c6a0f6',
}

config.window_padding = {
    left = 4,
    right = 4,
    top = 4,
    bottom = 0,
}

config.default_prog = { "/usr/bin/zsh" }
config.line_height = 1
config.animation_fps = 60
--config.cursor_blink_ease_in = "Linear"
--config.cursor_blink_ease_out = "Linear"

config.keys = {
    -- Turn off the default CMD-m Hide action, allowing CMD-m to
    -- be potentially recognized and handled by the tab
    {
        key = 'Enter',
        mods = 'ALT',
        action = wezterm.action.DisableDefaultAssignment,
    },
}

return config

