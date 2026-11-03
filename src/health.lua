-- A health bar under each player's card, as wide as the card: red for health, a white stretch that
-- lags behind a loss, dark red while downed and bleeding out, dark grey while dead. Remote players'
-- hitpoints are replicated, so every card has one.
--
-- The cards sit along the bottom of the screen in the HUD's 1280x720 space, y up, each growing upward
-- from y = 0 at Hud:get_player_hud_pos(slot) (hud.lua:1412). The space just under a card is empty.
local M = {}

local function g(name) return rawget(_G, name) end

local HEIGHT = 9 -- design units
local GAP = 3 -- between the card's bottom and the bar
local Z = 20
local HOLD = 1 -- seconds the lag stays where it was before draining
local DRAIN = 0.8 -- of the bar per second

local lags = {}

local function clamp(x) return math.max(0, math.min(1, x)) end

-- The lag for one slot: where the bar was, held a moment after each loss, then draining down.
local function lag_of(slot, pct, dt)
	local s = lags[slot]
	if not s or pct >= s.at then
		s = { at = pct, hold = 0 }
		lags[slot] = s
		return pct
	end
	if pct < (s.last or pct) then s.hold = HOLD end
	s.last = pct
	if s.hold > 0 then
		s.hold = s.hold - dt
	else
		s.at = math.max(pct, s.at - DRAIN * dt)
	end
	return s.at
end

local DEAD_STATES = { dead = true, countdown = true, wait_for_spawn = true }

local function draw(hud, dt, unit, slot, hs)
	local info = hud.hud_info and hud.hud_info[slot]
	local gui = hud.hd_gui
	if not (info and gui) or hud.hidden or hud.enabled == false then return end
	local V3, V2, C = g("Vector3"), g("Vector2"), g("Color")
	local w = (info.width or 248) + 4
	local x, y = -2, -(GAP + HEIGHT)
	gui:move(hud:get_player_hud_pos(slot))
	local dead = not unit or not hs or hs.is_dead or DEAD_STATES[info.state]
	if dead then
		lags[slot] = nil
		gui:rect(V3(x, y, Z), V2(w, HEIGHT), C(255, 70, 70, 70))
	else
		local max = hs.max_hitpoints or 100
		local hp = hs.hitpoints or max
		gui:rect(V3(x, y, Z), V2(w, HEIGHT), C(160, 20, 20, 20))
		if hp > 0 then
			local pct = clamp(hp / max)
			local lag = lag_of(slot, pct, dt or 0)
			if lag > pct then gui:rect(V3(x + w * pct, y, Z + 1), V2(w * (lag - pct), HEIGHT), C(230, 255, 255, 255)) end
			if pct > 0 then gui:rect(V3(x, y, Z + 2), V2(w * pct, HEIGHT), C(255, 220, 45, 30)) end
		else
			-- Downed: what's left of the bleed-out pool, constitution being negative.
			lags[slot] = nil
			local pool = -(hs.constitution or -100)
			local left = pool > 0 and clamp((hp + pool) / pool) or 0
			if left > 0 then gui:rect(V3(x, y, Z + 2), V2(w * left, HEIGHT), C(255, 120, 20, 15)) end
		end
	end
	gui:move(V3(0, 0, 0))
end

function M.install(active)
	local failed = false
	obsidian.hook("Hud", "draw_hud", function(original, self, dt, unit, name, slot, screen_pos, health_state, ...)
		local r = { original(self, dt, unit, name, slot, screen_pos, health_state, ...) }
		if active() then
			local ok, err = pcall(draw, self, dt, unit, slot, health_state)
			if not ok and not failed then
				failed = true
				obsidian.log("betterhud: health bar: " .. tostring(err))
			end
		end
		return unpack(r)
	end)
end

return M
