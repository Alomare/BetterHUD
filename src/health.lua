-- A health bar under each player's card, as wide as the card, in missions: red for health, white
-- chunks that fade out where health was lost, as the game's own bars do, dark red while downed and
-- bleeding out, and none while dead. While downed, a yellow bar half as tall shows how far getting
-- back up has come. Remote players' hitpoints are replicated, so every card has a health bar.
--
-- The cards sit along the bottom of the screen in the HUD's 1280x720 space, y up, each growing upward
-- from y = 0 at Hud:get_player_hud_pos(slot) (hud.lua:1412). The space just under a card is empty.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local HEIGHT = 9 -- design units
local GAP = 0 -- between the card's bottom and the bar: none, the bar sits against the card
local Z = 20
local CHUNK_LIFE, CHUNKS = 1, 5 -- a lost stretch fades out in this many seconds; this many at once

local bars = {}

local function clamp(x) return math.max(0, math.min(1, x)) end

-- Each loss leaves a white chunk where the health was, fading out, as the game's own bars do
-- (hud.lua:461-476). A heal drops the chunks it covers.
local function chunks_of(slot, pct, dt)
	local b = bars[slot]
	if not b then
		b = { pct = pct, chunks = {} }
		bars[slot] = b
	end
	if pct < b.pct - 1e-4 then
		table.insert(b.chunks, { from = pct, to = b.pct, life = CHUNK_LIFE })
		if #b.chunks > CHUNKS then table.remove(b.chunks, 1) end
	end
	for i = #b.chunks, 1, -1 do
		local c = b.chunks[i]
		c.life = c.life - dt
		if c.life <= 0 or pct >= c.to then table.remove(b.chunks, i) else c.from = math.max(c.from, pct) end
	end
	b.pct = pct
	return b.chunks
end

local DEAD_STATES = { dead = true, countdown = true, wait_for_spawn = true }

-- In the look of the card above: a dark backing, a darker track inset in it, the game's own health
-- red (hud_settings.lua) with a lighter top edge.
local BACK, TRACK = { 170, 22, 24, 26 }, { 200, 8, 9, 10 }
local RED, RED_TOP = { 255, 255, 55, 25 }, { 255, 255, 130, 95 }
local LAG, DOWNED = { 255, 255, 255 }, { 255, 130, 20, 15 }
local YELLOW, YELLOW_TOP = { 255, 255, 190, 17 }, { 255, 255, 225, 120 }

local function rect(gui, x, y, z, w, h, c)
	if w <= 0 then return end
	gui:rect(g("Vector3")(x, y, z), g("Vector2")(w, h), g("Color")(c[1], c[2], c[3], c[4]))
end

-- Health and the most it can be, inside the bar at its left, in white over a shadow.
local TEXT_SIZE = 10 -- design units, about the bar's height
local TEXT_X, TEXT_Y = 4, 1.5 -- from the bar's bottom left to the words' baseline
local INK, SHADOW = { 255, 255, 255, 255 }, { 210, 0, 0, 0 }

local function numbers(gui, x, y, hp, max)
	local text = string.format("%d / %d", math.ceil(hp), math.floor(max + 0.5))
	local V3, C = g("Vector3"), g("Color")
	gui:set_current_font("body_large")
	gui:text(text, V3(x + TEXT_X + 0.6, y + TEXT_Y - 0.6, Z + 5), C(SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4]), nil, TEXT_SIZE)
	gui:text(text, V3(x + TEXT_X, y + TEXT_Y, Z + 6), C(INK[1], INK[2], INK[3], INK[4]), nil, TEXT_SIZE)
end

-- A bar at x, y (its bottom left): backing, track, then a fill of `pct` with its top edge.
local function bar(gui, x, y, w, h, pct, fill, top)
	rect(gui, x - 1, y - 1, Z, w + 2, h + 2, BACK)
	rect(gui, x, y, Z + 1, w, h, TRACK)
	rect(gui, x, y, Z + 3, w * pct, h, fill)
	if top then rect(gui, x, y + h - 1, Z + 4, w * pct, 1, top) end
end

local function draw(hud, dt, unit, slot, hs, cs, show_numbers)
	local info = hud.hud_info and hud.hud_info[slot]
	local gui = hud.hd_gui
	if not (info and gui) or hud.hidden or hud.enabled == false then return end
	-- A dead player has no bar.
	if not unit or not hs or hs.is_dead or DEAD_STATES[info.state] then
		bars[slot] = nil
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
			bar(gui, x, y, w, HEIGHT, pct, RED, RED_TOP)
			for _, c in ipairs(chunks_of(slot, pct, dt or 0)) do
				rect(gui, x + w * c.from, y, Z + 2, w * (c.to - c.from), HEIGHT, { math.floor(230 * c.life / CHUNK_LIFE), LAG[1], LAG[2], LAG[3] })
			end
			if show_numbers then numbers(gui, x, y, hp, max) end
		else
			-- Downed: what's left of the bleed-out pool, constitution being negative, and below it how
			-- far getting up has come.
			bars[slot] = nil
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

-- active(): whether the bars show; numbers_on(): whether they show health as numbers too.
function M.install(active, numbers_on)
	local failed = false
	obsidian.hook("Hud", "draw_hud", function(original, self, dt, unit, name, slot, screen_pos, health_state, inventory_state, character_state, ...)
		local r = { original(self, dt, unit, name, slot, screen_pos, health_state, inventory_state, character_state, ...) }
		-- The ship's HUD has cards too, with no health to show.
		if active() and api.game.in_mission() then
			local ok, err = pcall(draw, self, dt, unit, slot, health_state, character_state, numbers_on and numbers_on())
			if not ok and not failed then
				failed = true
				obsidian.log("betterhud: health bar: " .. tostring(err))
			end
		end
		return unpack(r)
	end)
end

return M
