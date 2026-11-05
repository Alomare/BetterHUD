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

	{ "look: rounds yellow, fading to red from 30% to empty", function()
		local function same(a, b, what) for i = 1, 4 do eq(a[i], b[i], what) end end
		local fill, ccw, color, size = circle.look("firearm", 0.5, true, false, 30)
		eq(fill, 0.5, "magazine left") eq(ccw, false, "clockwise") same(color, circle.FILL, "yellow") eq(size, nil, "one band, no segments")
		same(select(3, circle.look("firearm", 0.3, true, false, 30)), circle.FILL, "still yellow at 30%")
		same(select(3, circle.look("firearm", 0, true, true, 30)), circle.WARN, "red at empty")
		local mid = select(3, circle.look("launcher", 0.15, true, false, 100))
		same(mid, circle.warmth(0.5), "half way at 15%, any weapon with rounds")
		eq(mid[2] < circle.FILL[2] and mid[2] > circle.WARN[2], true, "between the two")
	end },

	{ "look: a laser fills counter-clockwise with heat, swings yellow to red faster as it heats, and empties when overheated", function()
		local function same(a, b, what) for i = 1, 4 do eq(a[i], b[i], what) end end
		local fill, ccw, color, size = circle.look("beamweapon", 0.75, false, false)
		near(fill, 0.25, "heat") eq(ccw, true, "counter-clockwise") same(color, circle.FILL, "yellow") eq(size, nil, "one band")
		eq(circle.pulse_rate(0.4), 0, "no swing under half heat")
		near(circle.pulse_rate(0.5), circle.PULSE[1])
		near(circle.pulse_rate(1), circle.PULSE[2], "fastest at full heat")
		same(circle.heat_color(0.4, 0.5), circle.FILL, "yellow under half heat")
		same(circle.heat_color(0.8, 0), circle.FILL, "the swing starts yellow")
		same(circle.heat_color(0.8, 0.5), circle.WARN, "red half way through")
		fill = circle.look("beamweapon", 0, false, true)
		eq(fill, 0, "overheated: an empty ring, so the red flash and the reload button show")
		local _, _, empty = circle.reading({ heat = 1 })
		eq(empty, true, "full heat is overheated")
		_, _, empty = circle.reading({ heat = 0.99 })
		eq(empty, false)
	end },

	{ "react: running dry and overheating shake the ring, an overheat flashes white, a discharge fades a white ring", function()
		local function same(a, b, what) for i = 1, 4 do eq(a[i], b[i], what) end end
		local t = {}
		circle.react(t, "firearm", 0.1, true, false, nil, 1, 0.016)
		eq(t.shake, nil)
		circle.react(t, "firearm", 0, true, true, nil, 2, 0.016)
		eq(t.shake, 2, "the magazine ran dry")
		local dx, dy = circle.shake_offset(t, 2.05)
		eq(math.abs(dx) <= circle.SHAKE_UNITS and math.abs(dy) <= circle.SHAKE_UNITS, true, "slight")
		near(select(1, circle.shake_offset(t, 2 + circle.SHAKE + 0.01)), 0, "settled")
		circle.react(t, "firearm", 0, true, true, nil, 3, 0.016)
		eq(t.shake, 2, "once, not every frame it stays empty")

		local hot = {}
		circle.react(hot, "beamweapon", 0.2, false, false, nil, 5, 0.1)
		near(hot.phase, circle.pulse_rate(0.8) * 0.1, "the swing moves on")
		circle.react(hot, "beamweapon", 0, false, true, nil, 6, 0.1)
		eq(hot.burnt, 6) eq(hot.shake, 6)
		same(circle.burn_track(hot, 6), circle.WHITE, "white at the overheat")
		local later = circle.burn_track(hot, 6 + circle.BURN + circle.FLASH / 2)
		same(later, circle.HOT_RED, "then a strong red")

		local arc = { shot = 1 }
		circle.react(arc, "arcweapon", 0.2, false, false, 0.3, 7, 0.016)
		circle.react(arc, "arcweapon", 1, false, false, 0.3, 7.1, 0.016)
		eq(arc.discharged, 7.1, "let go at 80% charge") eq(arc.shake, 7.1) eq(arc.shot, nil, "hidden after the fade")
		near(circle.discharge_alpha(arc, 7.1), 1)
		eq(circle.discharge_alpha(arc, 7.1 + circle.DISCHARGE + 0.01), nil, "faded")
		local weak = {}
		circle.react(weak, "arcweapon", 0.9, false, false, 0.3, 8, 0.016)
		circle.react(weak, "arcweapon", 1, false, false, 0.3, 8.1, 0.016)
		eq(weak.discharged, nil, "not enough charge to fire: no discharge")
	end },

	{ "look: an arc weapon's ring fills with the charge, bright once it can fire", function()
		local fill, ccw, color = circle.look("arcweapon", 0.6, false, false, nil, 0.3)
		near(fill, 0.4, "the charge") eq(ccw, false, "clockwise") eq(color, circle.ARC, "past what it fires at")
		eq(circle.ARC[3] > circle.ARC[1], true, "blue")
		eq(select(3, circle.look("arcweapon", 0.8, false, false, nil, 0.3)), circle.ARC_LOW, "not enough to fire yet")
		eq(select(3, circle.look("arcweapon", 0.7, false, false, nil, 0.3)), circle.ARC, "just enough")
	end },

	{ "reading: a full arc charge is ready, not empty", function()
		local share, rounds, empty, size, ready = circle.reading({ heat = 1, min_heat_to_fire = 0.25 })
		near(share, 0) eq(rounds, false) eq(empty, false, "no flashing at full charge") eq(size, nil) near(ready, 0.25)
		eq(select(3, circle.reading({ heat = 1 })), true, "a laser at full heat overheats")
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
