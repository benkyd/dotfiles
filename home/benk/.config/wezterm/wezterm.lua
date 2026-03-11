local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

local is_macos = wezterm.target_triple:find('darwin') ~= nil

-- Shell — fish via Homebrew on macOS, system fish on Linux
if is_macos then
  config.default_prog = { '/opt/homebrew/bin/fish' }
  config.set_environment_variables = {
    PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  }
else
  config.default_prog = { '/usr/bin/fish' }
  config.enable_wayland = true
  config.kde_window_background_blur = true
end

config.hide_tab_bar_if_only_one_tab = true
config.font_size = 10.0
config.line_height = 1.0
config.adjust_window_size_when_changing_font_size = false
config.animation_fps = 60

config.color_scheme = 'Catppuccin Mocha'

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

if is_macos then
  config.macos_window_background_blur = 70
end

config.keys = {
    {
        key = 'Enter',
        mods = 'ALT',
        action = wezterm.action.DisableDefaultAssignment,
    },
}

return config
