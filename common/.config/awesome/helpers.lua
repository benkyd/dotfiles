local beautiful = require("beautiful")
local gears     = require("gears")
local wibox     = require("wibox")
local rubato    = require("plugins.rubato")

local helpers   = {}

helpers.rrect = function(rad)
	return function(cr,w,h)
		gears.shape.rounded_rect(cr,w,h,rad)
	end
end

helpers.prrect = function(rad,tl,tr,br,bl)
	return function(cr,w,h)
		gears.shape.partially_rounded_rect(cr,w,h,tl,tr,br,bl,rad)
	end
end

helpers.contains = function(t, i)
	for _, v in pairs(t) do
		if v == i then
			return true
		end
	end
	return false
end

helpers.join = function(t, d)
	local d = d or " "
	local out
	for _, v in ipairs(t) do
		if not out then
			out = tostring(v)
		else
			out = out .. d .. tostring(v)
		end
	end
	return out
end

helpers.combine = function(img1,col1,img2,col2,w,h)
	local w = w or 64
	local h = h or 64
	return wibox.widget.draw_to_image_surface (wibox.widget {
		wibox.widget.imagebox(gears.color.recolor_image(img1,col1)),
		wibox.widget.imagebox(gears.color.recolor_image(img2,col2)),
		layout = wibox.layout.stack },
		w,h)
end

return helpers
