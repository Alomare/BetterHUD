-- A health bar under each player's card, as wide as the card, in missions: red for health, a white
-- stretch that lags behind a loss, dark red while downed and bleeding out, and none while dead. While
-- downed, a yellow bar half as tall shows how far getting back up has come. Remote players' hitpoints
-- are replicated, so every card has a health bar.
--
-- The cards sit along the bottom of the screen in the HUD's 1280x720 space, y up, each growing upward
-- from y = 0 at Hud:get_player_hud_pos(slot) (hud.lua:1412). The space just under a card is empty.
local api = obsidian.import("obsidian.api")

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

-- In the look of the card above: a dark backing, a darker track inset in it, the game's own health
-- red (hud_settings.lua) with a lighter top edge.
local BACK, TRACK = { 170, 22, 24, 26 }, { 200, 8, 9, 10 }
local RED, RED_TOP = { 255, 255, 55, 25 }, { 255, 255, 130, 95 }
local LAG, DOWNED = { 230, 255, 255, 255 }, { 255, 130, 20, 15 }
local YELLOW, YELLOW_TOP = { 255, 255, 190, 17 }, { 255, 255, 225, 120 }

local function rect(gui, x, y, z, w, h, c)
	if w <= 0 then return end
	gui:rect(g("Vector3")(x, y, z), g("Vector2")(w, h), g("Color")(c[1], c[2], c[3], c[4]))
end

-- A bar at x, y (its bottom left): backing, track, then a fill of `pct` with its top edge.
local function bar(gui, x, y, w, h, pct, fill, top)
	rect(gui, x - 1, y - 1, Z, w + 2, h + 2, BACK)
	rect(gui, x, y, Z + 1, w, h, TRACK)
	rect(gui, x, y, Z + 3, w * pct, h, fill)
	if top then rect(gui, x, y + h - 1, Z + 4, w * pct, 1, top) end
end

local function draw(hud, dt, unit, slot, hs, cs)
	local info = hud.hud_info and hud.hud_info[slot]
	local gui = hud.hd_gui
	if not (info and gui) or hud.hidden or hud.enabled == false then return end
	-- A dead player has no bar.
	if not unit or not hs or hs.is_dead or DEAD_STATES[info.state] then
		lags[slot] = nil
		return
	end
	local w = (info.width or 248) + 2
	local x, y = -1, -(GAP + HEIGHT)
	gui:move(hud:get_player_hud_pos(slot))
	do
		local max = hs.max_hitpoints or 100
		local hp = hs.hitpoints or max
		if hp > 0 then
			local pct = clamp(hp / max)
			local lag = lag_of(slot, pct, dt or 0)
			bar(gui, x, y, w, HEIGHT, pct, RED, RED_TOP)
			if lag > pct then rect(gui, x + w * pct, y, Z + 2, w * (lag - pct), HEIGHT, LAG) end
		else
			-- Downed: what's left of the bleed-out pool, constitution being negative, and below it how
			-- far getting up has come.
			lags[slot] = nil
			local pool = -(hs.constitution or -100)
			bar(gui, x, y, w, HEIGHT, pool > 0 and clamp((hp + pool) / pool) or 0, DOWNED)
			local need = cs and tonumber(cs.get_up_presses_needed)
			if need and need > 0 then
				local h = HEIGHT / 2
				bar(gui, x, y - GAP - h, w, h, clamp((tonumber(cs.get_up_presses) or 0) / need), YELLOW, YELLOW_TOP)
			end
		end
	end
	gui:move(g("Vector3")(0, 0, 0))
end

function M.install(active)
	local failed = false
	obsidian.hook("Hud", "draw_hud", function(original, self, dt, unit, name, slot, screen_pos, health_state, inventory_state, character_state, ...)
		local r = { original(self, dt, unit, name, slot, screen_pos, health_state, inventory_state, character_state, ...) }
		-- The ship's HUD has cards too, with no health to show.
		if active() and api.game.in_mission() then
			local ok, err = pcall(draw, self, dt, unit, slot, health_state, character_state)
			if not ok and not failed then
				failed = true
				obsidian.log("betterhud: health bar: " .. tostring(err))
			end
		end
		return unpack(r)
	end)
end

return M
