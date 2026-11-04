-- The shadow over the player health and shield bars (src/health.lua).
local health = obsidian.module("src/health")

return {
	{ "the strips cover the bar: the shadow comes from the left and clears to the right", function()
		local strips = health.shade_strips(health.SHADE_STRIPS, health.SHADE_MAX)
		eq(#strips, health.SHADE_STRIPS, "strips")
		eq(strips[1].from, 0, "from the left end")
		near(strips[#strips].to, 1, "to the right end")
		for i = 2, #strips do
			near(strips[i].from, strips[i - 1].to, "no gap between strips")
			eq(strips[i].alpha < strips[i - 1].alpha, true, "lighter to the right")
		end
		eq(strips[#strips].alpha <= 5, true, "almost clear at the right")
		eq(strips[1].alpha <= health.SHADE_MAX, true, "no darker than the most")
		eq(strips[1].alpha >= health.SHADE_MAX - 5, true, "darkest at the left")
		eq(health.SHADE_MAX <= 96, true, "subtle")
	end },

	{ "a very thin black outline at 75% opacity", function()
		eq(health.OUTLINE[1], 191, "75% opacity")
		eq(health.OUTLINE[2] + health.OUTLINE[3] + health.OUTLINE[4], 0, "black")
		eq(health.outline_pixels(1), 1, "720p: one pixel")
		eq(health.outline_pixels(1.5), 1, "1080p: one pixel")
		eq(health.outline_pixels(3), 2, "4K: two pixels")
	end },

	{ "shield fill", function()
		eq(health.shield_fill(nil), nil, "no shield")
		eq(health.shield_fill({ shield_activated = false, shieldpoints = 5, max_shieldpoints = 10 }), nil, "off")
		near(health.shield_fill({ shield_activated = true, shieldpoints = 5, max_shieldpoints = 10 }), 0.5, "half")
	end },
}
