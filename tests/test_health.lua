-- The shadow over the player health and shield bars (src/health.lua).
local health = obsidian.module("src/health")

return {
	{ "the strips cover the bar and darken from left to right", function()
		local strips = health.shade_strips(health.SHADE_STRIPS, health.SHADE_MAX)
		eq(#strips, health.SHADE_STRIPS, "strips")
		eq(strips[1].from, 0, "from the left end")
		near(strips[#strips].to, 1, "to the right end")
		for i = 2, #strips do
			near(strips[i].from, strips[i - 1].to, "no gap between strips")
			eq(strips[i].alpha > strips[i - 1].alpha, true, "darker to the right")
		end
		eq(strips[1].alpha <= 5, true, "almost clear at the left")
		eq(strips[#strips].alpha <= health.SHADE_MAX, true, "no darker than the most")
		eq(health.SHADE_MAX <= 96, true, "subtle")
	end },

	{ "shield fill", function()
		eq(health.shield_fill(nil), nil, "no shield")
		eq(health.shield_fill({ shield_activated = false, shieldpoints = 5, max_shieldpoints = 10 }), nil, "off")
		near(health.shield_fill({ shield_activated = true, shieldpoints = 5, max_shieldpoints = 10 }), 0.5, "half")
	end },
}
