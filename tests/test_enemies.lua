-- Enemy health bars: the white stretch of lost health, the size, and the edge for enemies out of view
-- (src/enemies.lua).
local enemies = obsidian.module("src/enemies")

return {
	{ "the white stretch: hits renew it, and it fades all at once after the last", function()
		local b = { pct = 1 }
		enemies.lag_step(b, 0.8, 0)
		eq(b.lag.top, 1, "from where health stood")
		eq(enemies.lag_alpha(b.lag, 0.3), 1, "full strength soon after")
		enemies.lag_step(b, 0.6, 0.4)
		eq(b.lag.top, 1, "a second hit keeps the top: one stretch")
		eq(enemies.lag_alpha(b.lag, 0.4 + enemies.LAG_HOLD), 1, "held after the last hit")
		near(enemies.lag_alpha(b.lag, 0.4 + enemies.LAG_HOLD + enemies.LAG_FADE / 2), 0.5, "half faded")
		-- A hit while it fades brings it back.
		local t = 0.4 + enemies.LAG_HOLD + enemies.LAG_FADE / 2
		enemies.lag_step(b, 0.5, t)
		eq(b.lag.top, 1, "same stretch")
		eq(enemies.lag_alpha(b.lag, t), 1, "renewed")
		-- Once gone, the next hit starts from the health then.
		local gone = t + enemies.LAG_HOLD + enemies.LAG_FADE + 0.01
		enemies.lag_step(b, 0.5, gone)
		eq(b.lag, nil, "gone")
		enemies.lag_step(b, 0.3, gone + 1)
		eq(b.lag.top, 0.5, "a new stretch from the health then")
	end },

	{ "the white stretch fades a little faster than 1.8's chunks", function()
		eq(enemies.LAG_FADE < 1, true, "fade")
		eq(enemies.LAG_HOLD > 0, true, "waits for the last hit")
	end },

	{ "a heal past the top drops the stretch", function()
		local b = { pct = 1 }
		enemies.lag_step(b, 0.5, 0)
		enemies.lag_step(b, 1, 0.1)
		eq(b.lag, nil, "healed")
	end },

	{ "bars as tall as in 1.8, with an outline twice as thick, and a little see-through", function()
		local old = { 4.1, 5.4, 6.6, 8.3 }
		for i, t in ipairs(enemies.TIERS) do near(t.h, old[i], "tier " .. i) end
		eq(enemies.OUTLINE_PX, 2, "outline pixels")
		eq(enemies.OPACITY < 1 and enemies.OPACITY >= 0.75, true, "slightly less opaque")
	end },

	{ "an enemy out of view: the bar waits on the nearest edge, with a gap", function()
		local x, y = enemies.pin(-300, 500, 60, 8, 1920, 1080, 12)
		eq(x, 12, "left edge")
		eq(y, 500, "same height")
		x, y = enemies.pin(2500, 2000, 60, 8, 1920, 1080, 12)
		eq(x, 1920 - 12 - 60, "right edge")
		eq(y, 1080 - 12 - 8, "top edge")
		x, y = enemies.pin(900, -50, 60, 8, 1920, 1080, 12)
		eq(x, 900, "same place across")
		eq(y, 12, "bottom edge")
	end },

	{ "status build-up: set, capped, cleared, and dropped with its unit", function()
		rawset(_G, "Unit", { alive = function(u) return u.alive ~= false end })
		local a, b = {}, {}
		eq(enemies.buildup(a, "fire", 0.4), true)
		eq(enemies.buildup(a, "poison", 1.7), true)
		near(enemies.buildup_of(a, "fire"), 0.4)
		eq(enemies.buildup_of(a, "poison"), 1, "no more than full")
		eq(enemies.buildup(a, "acid", 0.5), false, "a kind without a color")
		eq(enemies.buildup(a, "fire", "half"), false)
		eq(enemies.buildup(a, "fire", nil), true)
		eq(enemies.buildup_of(a, "fire"), nil, "cleared")
		a.alive = false
		eq(enemies.buildup(b, "stun", 0.2), true)
		eq(enemies.buildup_of(a, "poison"), nil, "gone with its unit")
		near(enemies.buildup_of(b, "stun"), 0.2)
		rawset(_G, "Unit", nil)
	end },
}
