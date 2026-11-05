-- The grenade counter's looks and the charge meter's table (src/grenades.lua).
local grenades = obsidian.module("src/grenades")

local function look(l, a, r) eq(l[1], a, "opacity") eq(l[2], r, "red") end

return {
	{ "without the counter the slots look as the game draws them", function()
		local s1, s2 = grenades.looks(0, false, false)
		look(s1, 1, 128) look(s2, 1, 128)
		s1, s2 = grenades.looks(1, false, false)
		look(s1, 1, 255) look(s2, 1, 128)
		s1, s2 = grenades.looks(5, false, false)
		look(s1, 1, 255) look(s2, 1, 255)
	end },

	{ "with the counter the lower icon is clear and the upper one is lit from one grenade", function()
		local s1, s2 = grenades.looks(0, true, false)
		look(s1, 0, 255) look(s2, 1, 128)
		s1, s2 = grenades.looks(1, true, false)
		look(s1, 0, 255) look(s2, 1, 255)
	end },

	{ "a meter dims the upper icon, with the counter on or off", function()
		local _, s2 = grenades.looks(3, true, true)
		look(s2, grenades.DIM, 255)
		_, s2 = grenades.looks(0, false, true)
		look(s2, grenades.DIM, 255)
	end },

	{ "the counter reads x and the count, grey at none", function()
		local t, c = grenades.counter(0)
		eq(t, "x0") eq(c[1], 128)
		t, c = grenades.counter(1)
		eq(t, "x1") eq(c[1], 255)
		eq((grenades.counter(15)), "x15")
	end },

	{ "grenade_meter sets, clamps and clears", function()
		local unit = {}
		eq(grenades.meter(unit, 0.5), true)
		eq(grenades.meter_of(unit), 0.5)
		grenades.meter(unit, 2)
		eq(grenades.meter_of(unit), 1)
		eq(grenades.meter(unit, "x"), false)
		eq(grenades.meter_of(unit), 1)
		eq(grenades.meter(unit, nil), true)
		eq(grenades.meter_of(unit), nil)
		eq(grenades.meter(nil, 0.5), false)
	end },
}
