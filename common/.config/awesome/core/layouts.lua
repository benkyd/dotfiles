local layout = require("awful").layout

layout.layouts = {
    layout.suit.spiral.dwindle,
    layout.suit.floating,
    layout.suit.tile,
    layout.suit.tile.left,
    layout.suit.tile.bottom,
    layout.suit.tile.top,
    layout.suit.fair,
    layout.suit.fair.horizontal,
    layout.suit.spiral,
    layout.suit.max,
    layout.suit.max.fullscreen,
    layout.suit.magnifier,
    layout.suit.corner.nw,
}
