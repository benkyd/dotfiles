local awful = require("awful")

local autostart = {
    ["picom"] = "/usr/bin/picom -b --config /home/$USER/.config/awesome/config/picom.conf",
    ["volumeicon"] = "/usr/bin/volumeicon",
    ["xdilehook"] = "/usr/bin/xidlehook --not-when-fullscreen --not-when-audio --timer 600 'blurlock' ''",
    ["nm-applet"] = "/usr/bin/nm-applet",
    ["xfce4-power-manager"] = "/usr/bin/xfce4-power-manager",
}

for command_name, command in pairs(autostart) do
    awful.spawn.with_shell(string.format(
        "pgrep -u $USER '%s' > /dev/null || (%s)",
        command_name, command
    ))
end
