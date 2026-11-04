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

	{ "the circle sits further right than in 1.7", function()
		eq(reload.RIGHT > 34, true, "moved right")
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
