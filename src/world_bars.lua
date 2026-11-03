-- The game's own bars over each Helldiver, which Better HUD's bars under the cards stand in for: the
-- health bar and the bar of getting back up when downed. Both are drawn by
-- Hud.draw_player_name_in_world (hud.lua:1568, 1586-1596), so they go only while that runs: the health
-- bar by a draw_health_bar that skips players' bars, the get-up bar by see-through colours.
local M = {}

local function g(name) return rawget(_G, name) end

local hidden_colours

local function see_through()
	if hidden_colours then return hidden_colours end
	local Q = g("QuaternionAux")
	hidden_colours = { background = Q.box_elements({}, 0, 0, 0, 0), foreground = Q.box_elements({}, 0, 0, 0, 0) }
	return hidden_colours
end

-- hide_health(), hide_get_up(): whether each is hidden now.
function M.install(hide_health, hide_get_up)
	local failed = false
	obsidian.hook("Hud", "draw_player_name_in_world", function(original, self, ...)
		local health, get_up = hide_health(), hide_get_up()
		if not (health or get_up) then return original(self, ...) end
		local real_draw, bars, real_get_up
		if health then
			real_draw = self.draw_health_bar
			-- An own field over the class's: only this call, and only a player's bar.
			self.draw_health_bar = function(s, dt, gui, ui_state, hs, pos, alpha, kind, ...)
				if kind == "player" then return end
				return real_draw(s, dt, gui, ui_state, hs, pos, alpha, kind, ...)
			end
		end
		if get_up then
			local ok = pcall(function()
				bars = g("HudSettings").settings.player_hud.bars
				real_get_up = bars.get_up_bar
				local copy = {}
				for k, v in pairs(real_get_up) do copy[k] = v end
				copy.colors = see_through()
				bars.get_up_bar = copy
			end)
			if not ok then bars = nil end
		end
		local r = { pcall(original, self, ...) }
		if health then self.draw_health_bar = nil end
		if bars then bars.get_up_bar = real_get_up end
		if not r[1] then
			if not failed then
				failed = true
				obsidian.log("betterhud: bars over players: " .. tostring(r[2]))
			end
			return
		end
		return unpack(r, 2)
	end)
end

return M
