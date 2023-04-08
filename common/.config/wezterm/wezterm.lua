local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end


config.hide_tab_bar_if_only_one_tab = true
config.font = wezterm.font("DejaVu Sans Mono")
config.font_size = 10.0
config.adjust_window_size_when_changing_font_size = false

config.color_scheme = 'Catppuccin Macchiato'
config.window_background_opacity = 0.85

config.window_padding = {
    left = '0.5cell',
    right = '0.5cell',
    top = '0.3cell',
    bottom = '0.3cell',
}

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

