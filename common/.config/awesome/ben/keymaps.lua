local gears = require("gears")
local awful = require("awful")
local keys = Ben.keys
local programs = Ben.programs

awful.keyboard.append_global_keybindings({
  awful.key({ keys.mod, keys.shift }, "r", function()
    awesome.restart()
  end),

  --[[ very important applications ]] --

  awful.key({ keys.mod }, keys.enter, function()
    awesome.spawn(programs.terminal)
  end),

  awful.key({ keys.mod }, "d", function()
    awesome.spawn(programs.launcher)
  end),

  awful.key({ keys.mod }, "b", function()
    awesome.spawn(programs.browser)
  end),

  awful.key({ keys.mod }, "e", function()
    awesome.spawn(programs.filemanager)
  end),

  --[[awful.key({ keys.mod }, "m", function()]]
    --[[local rofi_beats = os.getenv("HOME") .. "/.local/bin/scripts/rofi-beats.sh"]]
    --[[awesome.spawn(rofi_beats)]]
    --[[end),]]

    --[[ window management ]] --
    awful.key({ keys.mod }, "h", function()
      awful.client.focus.global_bydirection("left")
    end),

    awful.key({ keys.mod }, "j", function()
      awful.client.focus.global_bydirection("down")
    end),

    awful.key({ keys.mod }, "k", function()
      awful.client.focus.global_bydirection("up")
    end),

    awful.key({ keys.mod }, "l", function()
      awful.client.focus.global_bydirection("right")
    end),

    awful.key({ keys.mod, keys.ctrl }, "h", function()
      awful.client.swap.global_bydirection("left")
    end),

    awful.key({ keys.mod, keys.ctrl }, "j", function()
      awful.client.swap.global_bydirection("down")
    end),

    awful.key({ keys.mod, keys.ctrl }, "k", function()
      awful.client.swap.global_bydirection("up")
    end),

    awful.key({ keys.mod, keys.ctrl }, "l", function()
      awful.client.swap.global_bydirection("right")
    end),

    awful.key({ keys.mod, keys.shift }, "h", function()
      awful.tag.incmwfact(-0.05)
    end),

    awful.key({ keys.mod, keys.shift }, "l", function()
      awful.tag.incmwfact(0.05)
    end),

    awful.key({ keys.mod, keys.shift }, "j", function()
      awful.client.incwfact(0.05)
    end),

    awful.key({ keys.mod, keys.shift }, "k", function()
      awful.client.incwfact(-0.05)
    end),

    awful.key({ keys.mod }, "u", function()
      awful.client.urgent.jumpto()
    end),



    --[[ Switching between tags ]] --

    awful.key({ keys.mod }, "#10", function()
      local tag = awful.screen.focused().tags[1]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#11", function()
      local tag = awful.screen.focused().tags[2]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#12", function()
      local tag = awful.screen.focused().tags[3]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#13", function()
      local tag = awful.screen.focused().tags[4]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#14", function()
      local tag = awful.screen.focused().tags[5]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#15", function()
      local tag = awful.screen.focused().tags[6]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#16", function()
      local tag = awful.screen.focused().tags[7]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#17", function()
      local tag = awful.screen.focused().tags[8]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#18", function()
      local tag = awful.screen.focused().tags[9]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod }, "#19", function()
      local tag = awful.screen.focused().tags[10]
      if tag then
        tag:view_only()
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#10", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[1]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#11", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[2]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#12", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[3]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#13", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[4]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#14", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[5]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#15", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[6]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#16", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[7]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#17", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[8]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#18", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[9]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),

    awful.key({ keys.mod, keys.shift }, "#19", function()
      if not client.focus then
        return
      end

      local tag = client.focus.screen.tags[10]
      if tag then
        client.focus:move_to_tag(tag)
      end
    end),
    awful.key({}, "XF86MonBrightnessUp",
    function()
      awful.spawn("xbacklight -inc 10", false)
      awesome.emit_signal("backlight_change")
    end
    --  {description = "brightness up", group = "hotkeys"}
    ),
    awful.key({}, "XF86MonBrightnessDown",
    function()
      awful.spawn("xbacklight -dec 10", false)
      awesome.emit_signal("backlight_change")
    end
    --{description = "brightness down", group = "hotkeys"}
    ),
    -- ALSA volume control
    awful.key({}, "XF86AudioRaiseVolume",
    function()
      awful.spawn("amixer -D pulse sset Master 5%+", false)
      awesome.emit_signal("volume_change")
    end
    --{description = "volume up", group = "hotkeys"}
    ),
    awful.key({}, "XF86AudioLowerVolume",
    function()
      awful.spawn("amixer -D pulse sset Master 5%-", false)
      awesome.emit_signal("volume_change")
    end
    --{description = "volume down", group = "hotkeys"}
    ),
    awful.key({}, "XF86AudioMute",
    function()
      awful.spawn("amixer -D pulse set Master 1+ toggle", false)
      awesome.emit_signal("volume_change")
    end
    --{description = "toggle mute", group = "hotkeys"}
    ),
    awful.key({}, "XF86AudioNext",
    function()
      awful.spawn("mpc next", false)
    end
    --{description = "next music", group = "hotkeys"}
    ),
    awful.key({}, "XF86AudioPrev",
    function()
      awful.spawn("mpc prev", false)
    end
    --{description = "previous music", group = "hotkeys"}
    ),
    awful.key({}, "XF86AudioPlay",
    function()
      awful.spawn("mpc toggle", false)
    end
    --{description = "play/pause music", group = "hotkeys"}
    ),
    awful.key({}, "Print",
    function()
      awful.spawn("flameshot gui", false)
    end
    ),
  })


  client.connect_signal("request::default_keybindings", function()
    awful.keyboard.append_client_keybindings({
      awful.key({ keys.mod, keys.shift }, "q", function(c)
        c:kill()
      end),

      awful.key({ keys.mod }, keys.space, function(c)
        c.floating = not c.floating
        c:raise()
      end),

      awful.key({ keys.mod }, "f", function(c)
        c.fullscreen = not c.fullscreen
        c:raise()
      end),
    })
  end)

  client.connect_signal("request::default_mousebindings", function()
    awful.mouse.append_client_mousebindings({
      awful.button({}, 1, function(c)
        c:activate({ context = "mouse_click" })
      end),

      awful.button({ keys.mod }, 1, function(c)
        c:activate({
          context = "mouse_click",
          action = "mouse_move",
        })
      end),

      awful.button({ keys.mod }, 3, function(c)
        c:activate({
          context = "mouse_click",
          action = "mouse_resize",
        })
      end),
    })
  end)

  -- vim: filetype=lua:expandtab:shiftwidth=2:tabstop=2:softtabstop=2:textwidth=80
