-- Damage numbers: the two modes' timing and curves (src/numbers.lua).
local numbers = obsidian.module("src/numbers")

local function fresh() return {}, setmetatable({}, { __mode = "k" }) end

return {
	{ "stacked: a number for each hit, rising from the first frame", function()
		local list, open = fresh()
		local a = numbers.add(list, open, "bug", 10, "enemy", nil, "stacked", 0)
		local b = numbers.add(list, open, "bug", 5, "enemy", nil, "stacked", 0.05)
		eq(#list, 2, "numbers")
		eq(a ~= b, true, "separate numbers")
		local rise0, alpha0 = numbers.look(a, 0)
		eq(rise0, 0, "rise at the start")
		eq(alpha0, 1, "visible at the start")
		local rise = numbers.look(a, numbers.LIFE * 0.05)
		eq(rise > 0, true, "already rising")
	end },

	{ "stacked: faster at the start than an ease-out square", function()
		local list, open = fresh()
		local n = numbers.add(list, open, "bug", 10, "enemy", nil, "stacked", 0)
		for _, f in ipairs({ 0.05, 0.1, 0.2, 0.3 }) do
			local rise = numbers.look(n, f * numbers.LIFE)
			eq(rise > 1 - (1 - f) * (1 - f), true, "rise at " .. f)
		end
		-- Clears the height of a number (15 design units) within a fifth of a second.
		eq(numbers.look(n, 0.2) * numbers.RISE >= 15, true, "out of the way in 0.2 s")
		local prev = -1
		for i = 0, 20 do
			local rise = numbers.look(n, i / 20 * numbers.LIFE)
			eq(rise >= prev, true, "never falls back")
			prev = rise
		end
		local rise, alpha = numbers.look(n, numbers.LIFE)
		near(rise, 1, "risen fully")
		near(alpha, 0, "gone at the end")
	end },

	{ "stacked: gone after LIFE", function()
		local list, open = fresh()
		numbers.add(list, open, "bug", 10, "enemy", nil, "stacked", 0)
		numbers.step(list, numbers.LIFE - 0.01)
		eq(#list, 1, "still there")
		numbers.step(list, numbers.LIFE)
		eq(#list, 0, "dropped")
	end },

	{ "accumulated: stays in place and adds every hit while it shows", function()
		local list, open = fresh()
		local n = numbers.add(list, open, "bug", 10, "enemy", nil, "accumulated", 0)
		numbers.add(list, open, "bug", 5, "enemy", nil, "accumulated", 0.5)
		eq(#list, 1, "one number")
		eq(n.amount, 15, "added up")
		local rise, alpha = numbers.look(n, 0.5 + numbers.HOLD)
		eq(rise, 0, "never rises")
		eq(alpha, 1, "full strength until HOLD after the last hit")
		rise, alpha = numbers.look(n, 0.5 + numbers.HOLD + numbers.FADE / 2)
		eq(rise, 0, "still in place while fading")
		near(alpha, 0.5, "half faded")
	end },

	{ "accumulated: a hit while it fades still adds to it", function()
		local list, open = fresh()
		local n = numbers.add(list, open, "bug", 10, "enemy", nil, "accumulated", 0)
		local t = numbers.HOLD + numbers.FADE * 0.9
		numbers.step(list, t)
		local m = numbers.add(list, open, "bug", 7, "enemy", nil, "accumulated", t)
		eq(m, n, "same number")
		eq(n.amount, 17, "added")
		local _, alpha = numbers.look(n, t)
		eq(alpha, 1, "back to full strength")
	end },

	{ "accumulated: a new number only once the old one has gone", function()
		local list, open = fresh()
		local n = numbers.add(list, open, "bug", 10, "enemy", nil, "accumulated", 0)
		local gone = numbers.HOLD + numbers.FADE
		-- Gone, even before step drops it.
		local m = numbers.add(list, open, "bug", 3, "enemy", nil, "accumulated", gone)
		eq(m ~= n, true, "a new number")
		eq(n.amount, 10, "the old one kept the total")
		numbers.step(list, gone)
		eq(#list, 1, "the old one dropped")
		eq(list[1], m, "the new one stays")
	end },

	{ "accumulated: one number for each target", function()
		local list, open = fresh()
		numbers.add(list, open, "bug", 10, "enemy", nil, "accumulated", 0)
		numbers.add(list, open, "cyborg", 4, "enemy", nil, "accumulated", 0.1)
		numbers.add(list, open, "bug", 1, "enemy", nil, "accumulated", 0.2)
		eq(#list, 2, "two targets")
		eq(list[1].amount, 11, "first")
		eq(list[2].amount, 4, "second")
	end },

	{ "a number marked gone takes no more hits", function()
		local list, open = fresh()
		local n = numbers.add(list, open, "bug", 10, "enemy", nil, "accumulated", 0)
		n.gone = true
		local m = numbers.add(list, open, "bug", 2, "enemy", nil, "accumulated", 0.1)
		eq(m ~= n, true, "a new number")
	end },

	{ "no number for no damage", function()
		local list, open = fresh()
		eq(numbers.add(list, open, "bug", 0, "enemy", nil, "stacked", 0), nil, "zero")
		eq(#list, 0, "none")
	end },

	{ "the shadow: a third closer than Helldivers Arcade's, and 25% less opaque", function()
		near(numbers.shadow_offset(15), 2 * 2 / 3, "small text")
		near(numbers.shadow_offset(22.5), 2 * 2 / 3, "1080p")
		near(numbers.shadow_offset(45), 3 * 2 / 3, "big text")
		eq(numbers.SHADOW[4], 144, "192 less 25%")
	end },
}
