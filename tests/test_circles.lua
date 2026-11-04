-- The reload circle and the ammo circle (src/reload.lua, src/ammo_circle.lua).
local reload = obsidian.module("src/reload")
local circle = obsidian.module("src/ammo_circle")

return {
	{ "reload progress from the weapon's state", function()
		eq(reload.progress({ reload_time = -1, reload_duration = 2 }), nil, "not reloading")
		near(reload.progress({ reload_time = 1.5, reload_duration = 2 }), 0.25, "a quarter")
		eq(reload.progress({ reload_time = 1, reload_duration = 2, is_reloading = false }), nil, "stopped")
	end },

	{ "a finished reload ring grows and fades out", function()
		local grow, alpha = reload.finish(0)
		eq(grow, 1, "starts at full size")
		eq(alpha, 1, "starts visible")
		eq(reload.finish(0.1), nil, "gone after a tenth of a second")
	end },

	{ "the circles sit to the left of the Helldiver, a little up", function()
		eq(reload.LEFT > 34, true, "as far out as before, to the left")
		eq(reload.RIGHT, nil, "not to the right")
		eq(reload.UP > 0 and reload.UP < 20, true, "a little up")
	end },

	{ "the shadow is darkest at the bottom left and clears at the top right", function()
		near(reload.shadow_at(math.pi / 4), 0, "top right")
		near(reload.shadow_at(math.pi * 5 / 4), 1, "bottom left")
		near(reload.shadow_at(0), reload.shadow_at(math.pi / 2), "top as light as the right", 1e-9)
		near(reload.shadow_at(math.pi), reload.shadow_at(math.pi * 3 / 2), "bottom as dark as the left", 1e-9)
		eq(reload.shadow_at(math.pi) > reload.shadow_at(0), true, "bottom darker than the top")
		near(reload.shadow_at(math.pi * 3 / 4), 0.5, "bottom right half way", 1e-9)
		near(reload.shadow_at(math.pi * 7 / 4), 0.5, "top left half way", 1e-9)
		local lit, dark = reload.shaded(circle.FILL, math.pi / 4), reload.shaded(circle.FILL, math.pi * 5 / 4)
		for i = 1, 3 do eq(lit[i], circle.FILL[i], "full color at the top right") end
		eq(dark[1] < lit[1], true, "darker at the bottom left")
		eq(dark[4], circle.FILL[4], "same opacity")
		eq(reload.SHADOW < 0.5, true, "a soft shadow")
	end },

	{ "one tone for each ring", function()
		eq(circle.LIT, nil, "no lighter inner half")
	end },

	{ "segments: one for each round, groups past 30", function()
		eq(circle.segments(1), nil, "one round: no dividers")
		eq(circle.segments(nil), nil, "no magazine")
		local step, count = circle.segments(6)
		eq(step, 1, "launcher") eq(count, 6, "six")
		step, count = circle.segments(30)
		eq(step, 1, "30 rounds") eq(count, 30, "thirty")
		step, count = circle.segments(45)
		eq(step, 5, "45 rounds in fives") eq(count, 9, "nine")
		step, count = circle.segments(110)
		eq(step, 5, "flamethrower") eq(count, 22, "22")
		step, count = circle.segments(150)
		eq(step, 5, "150") eq(count, 30, "thirty")
		step, count = circle.segments(750)
		eq(step, 25, "750") eq(count, 30, "thirty")
		step, count = circle.segments(1500)
		eq(step, 50, "1500") eq(count, 30, "thirty")
		for _, n in ipairs({ 31, 99, 151, 301, 2999 }) do
			eq(select(2, circle.segments(n)) <= circle.MAX_SEGMENTS, true, n .. " within the cap")
		end
	end },

	{ "dividers sit between the segments, one at the top", function()
		local a = reload.divider_angles(4)
		eq(#a, 4, "four segments, four dividers")
		near(a[1], math.pi / 2, "a quarter")
		near(a[3], math.pi * 3 / 2, "three quarters")
		eq(a[4], 0, "the top")
		eq(#reload.divider_angles(1), 0, "none for one round")
	end },

	{ "look: rounds yellow, red below a tenth", function()
		local fill, ccw, color, size = circle.look("firearm", 0.5, true, false, 30)
		eq(fill, 0.5, "magazine left") eq(ccw, false, "clockwise") eq(color, circle.FILL, "yellow") eq(size, 30, "dividers")
		eq(select(3, circle.look("firearm", 0.1, true, false, 30)), circle.FILL, "a tenth is not below")
		eq(select(3, circle.look("firearm", 2 / 30, true, false, 30)), circle.WARN, "red below a tenth")
		eq(select(3, circle.look("launcher", 0.05, true, false, 100)), circle.WARN, "any weapon with rounds")
	end },

	{ "look: a laser fills counter-clockwise with heat, red past nine tenths", function()
		local fill, ccw, color, size = circle.look("beamweapon", 0.75, false, false)
		near(fill, 0.25, "heat") eq(ccw, true, "counter-clockwise") eq(color, circle.FILL, "yellow") eq(size, nil, "no dividers")
		eq(select(3, circle.look("beamweapon", 0.11, false, false)), circle.FILL, "89% heat")
		eq(select(3, circle.look("beamweapon", 0.05, false, false)), circle.WARN, "95% heat")
		eq(select(3, circle.look("beamweapon", 0.5, false, true)), circle.WARN, "cooling after an overheat")
	end },

	{ "look: an arc weapon is blue", function()
		local fill, ccw, color = circle.look("arcweapon", 0.6, false, false)
		near(fill, 0.6, "share left") eq(ccw, false, "clockwise") eq(color, circle.ARC, "blue")
		eq(circle.ARC[3] > circle.ARC[1], true, "blue")
	end },

	{ "after a reload the ammo circle hides until the next shot", function()
		local t = {}
		circle.track(t, "gun", 0.5, 0)
		circle.track(t, "gun", 0.4, 1)
		eq(circle.alpha(t.shot, 1.5), 1, "showing after a shot")
		-- The magazine empties on the way out while reloading: no shot.
		circle.track(t, "gun", 0, 2, true)
		eq(t.shot, 1, "not a shot while reloading")
		circle.reloaded(t)
		circle.track(t, "gun", 1, 3)
		eq(circle.alpha(t.shot, 3), 0, "hidden after the reload")
		eq(circle.alpha(t.shot, 4), 0, "still hidden")
		circle.track(t, "gun", 29 / 30, 5)
		eq(circle.alpha(t.shot, 5), 1, "back with the next shot")
	end },

	{ "reading: rounds", function()
		local share, rounds, empty = circle.reading({ rounds = 15, magazine_capacity = 30 })
		near(share, 0.5, "half")
		eq(rounds, true, "counts rounds")
		eq(empty, false, "not empty")
		share, rounds, empty = circle.reading({ rounds = 0, magazine_capacity = 30 })
		eq(share, 0, "none left")
		eq(empty, true, "empty")
		-- An Extended Mag can hold more than the weapon's own size.
		eq(circle.reading({ rounds = 40, magazine_capacity = 30 }), 1, "never past full")
	end },

	{ "reading: heat", function()
		local share, rounds, empty = circle.reading({ heat = 0.25 })
		near(share, 0.75, "heat left")
		eq(rounds, false, "no rounds")
		eq(empty, false, "not overheated")
		share, rounds, empty = circle.reading({ heat = 1 })
		eq(share, 0, "none left")
		eq(empty, true, "overheated")
		eq(select(3, circle.reading({ heat = 0.6, overheated = true })), true, "cooling after an overheat")
	end },

	{ "reading: nothing to show", function()
		eq(circle.reading(nil), nil, "no state")
		eq(circle.reading({}), nil, "no rounds or heat")
		eq(circle.reading({ rounds = 3, magazine_capacity = 0 }), nil, "no magazine")
	end },

	{ "a shot is a share that went down on the same weapon", function()
		local t = {}
		circle.track(t, "gun", 1, 0)
		eq(t.shot, nil, "first frame")
		circle.track(t, "gun", 0.9, 1)
		eq(t.shot, 1, "fired")
		circle.track(t, "gun", 1, 2)
		eq(t.shot, 1, "a reload isn't a shot")
		circle.track(t, "pistol", 0.2, 3)
		eq(t.shot, 1, "a weapon swap isn't a shot")
		circle.track(t, "pistol", 0.1, 4)
		eq(t.shot, 4, "the new weapon fired")
	end },

	{ "shows for 8 seconds after the last shot, then fades out over 1", function()
		eq(circle.alpha(nil, 5), 0, "no shot yet")
		eq(circle.alpha(10, 10), 1, "just fired")
		eq(circle.alpha(10, 18), 1, "8 seconds on")
		near(circle.alpha(10, 18.5), 0.5, "half way out")
		eq(circle.alpha(10, 19), 0, "gone after 9")
		eq(circle.alpha(10, 30), 0, "stays gone")
	end },

	{ "empty: the track flashes from black to dark red and back", function()
		local a, b, c = circle.flash(0), circle.flash(circle.FLASH / 2), circle.flash(circle.FLASH)
		for i = 1, 4 do
			eq(a[i], circle.BLACK[i], "black at the start")
			eq(b[i], circle.RED[i], "red half way")
			eq(c[i], circle.BLACK[i], "black again")
		end
	end },

	{ "the reload button's key cap and name", function()
		local cap, key = circle.split_key("\238\128\128\194\172R\194\172")
		eq(cap, "\238\128\128", "cap")
		eq(key, "R", "key")
		cap, key = circle.split_key("\238\128\129")
		eq(cap, nil, "a pad button has no cap")
		eq(key, "\238\128\129", "the button itself")
		cap, key = circle.split_key(nil)
		eq(key, nil, "nothing")
	end },
}
