local awful = require("awful")

local autostart = {
  ["picom"] = "/usr/bin/picom -b --config /home/alphakeks/.config/picom/picom.conf",
  --["spectacle"] = "/usr/bin/spectacle -s",
  --["easyeffects"] = "/usr/bin/easyeffects --gapplication-service",
  --["signal-desktop"] = "/usr/bin/signal-desktop",
  --["discord"] = "/usr/bin/flatpak run com.discordapp.Discord",
  --["steam"] = "/usr/bin/steam -silent",
  --["nextcloud"] = "/usr/bin/nextcloud",
}

for command_name, command in pairs(autostart) do
  awful.spawn.with_shell(string.format(
    "pgrep -u $USER '%s' > /dev/null || (%s)",
    command_name, command
  ))
end
