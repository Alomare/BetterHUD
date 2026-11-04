-- Damage numbers: a number where damage lands. Damage to enemies is what this machine's players deal
-- (Obsidian API's combat.on_hit, 1.14.0); damage to players is what their replicated health loses.
-- Stacked: a number for each hit, which starts rising at once, fastest at the start, so the next one has
-- room. Accumulated: one number for each target that stays in place, adds every hit while it shows, and
-- fades out HOLD seconds after the last; the next hit after it has gone starts a new one.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
local api = obsidian.import("obsidian.api")

-- Photo Mode (or any mod) clearing the screen for pictures through Obsidian API's photo effect.
local function photo_mode()
	local effects = api.effects
	return effects ~= nil and effects.is_on ~= nil and effects.is_on("photo_mode") == true
end
local enemies = obsidian.module("src/enemies")

local M = {}

local function g(name) return rawget(_G, name) end

M.LIFE, M.RISE = 0.9, 30 -- stacked: seconds a number lasts; design units it climbs
M.HOLD, M.FADE = 0.7, 0.5 -- accumulated: seconds at full strength after the last hit; seconds to fade out
local SIZE = 15 -- design units
local SIDE = 16 -- design units right of the entity, for "next to the entity"
local LIMIT = 48
local ENEMY_INK, PLAYER_INK = { 255, 255, 255 }, { 255, 95, 75 }

local live = {}
local open = setmetatable({}, { __mode = "k" })
local last_hp = setmetatable({}, { __mode = "k" })

-- Whether a number has fully gone at time `now`.
function M.done(n, now)
	if n.gone then return true end
	if n.mode == "accumulated" then return now - n.last >= M.HOLD + M.FADE end
	return now - n.born >= M.LIFE
end

-- A new hit on `unit` worth `amount` at time `now`. kind: "enemy" or "player". at: where it landed, or nil.
-- mode: "stacked" or "accumulated". Answers the number it went into.
function M.add(list, opened, unit, amount, kind, at, mode, now)
	if amount <= 0 then return nil end
	local accumulated = mode == "accumulated"
	if accumulated then
		local n = opened[unit]
		if n and n.mode == "accumulated" and not M.done(n, now) then
			n.amount, n.last = n.amount + amount, now
			return n
		end
	end
	local n = { unit = unit, amount = amount, kind = kind, at = at, born = now, last = now,
		mode = accumulated and "accumulated" or "stacked", jitter = (#list % 5 - 2) * 6 }
	list[#list + 1] = n
	if accumulated then opened[unit] = n end
	while #list > LIMIT do
		table.remove(list, 1).gone = true
	end
	return n
end

-- Drops the numbers that have gone.
function M.step(list, now)
	for i = #list, 1, -1 do
		local n = list[i]
		if M.done(n, now) then
			n.gone = true
			table.remove(list, i)
		end
	end
end

-- How far it has risen (0 to 1) and how visible it is.
function M.look(n, now)
	if n.mode == "accumulated" then
		local idle = now - n.last
		if idle <= M.HOLD then return 0, 1 end
		return 0, math.max(0, 1 - (idle - M.HOLD) / M.FADE)
	end
	local f = math.max(0, math.min(1, (now - n.born) / M.LIFE))
	local left = 1 - f
	local rise = 1 - left * left * left
	local alpha = f < 0.45 and 1 or math.max(0, 1 - (f - 0.45) / 0.55)
	return rise, alpha
end

local function screen_of(n, position, scale)
	if position == "hit" and n.at then
		local x, y, inside = api.world.to_screen(n.at)
		return x, y, inside
	end
	if position == "bar" then
		-- A bar held on the screen's edge for an enemy out of view gets no number.
		local spot = enemies.drawn[n.unit]
		if spot and not spot.pinned then return spot.x, spot.y + 4 * scale, true end
	end
	local anchor = enemies.anchor_of(n.unit) or n.anchor
	if not anchor then return nil end
	n.anchor = anchor
	local x, y, inside = api.world.to_screen(anchor)
	if not x then return nil end
	return x + SIDE * scale, y, inside
end

-- A number in the look of Helldivers Arcade's stats under the player cards (cards.stat_line there): the
-- HUD's own font, Handel Gothic (fonts/handel_normal, "body_large", as hud.lua and font_settings.lua use
-- it), with the game's hard drop shadow down and to the right. The kit draws text one layer over the layer set,
-- so the shadow sits on the layer below the number.
M.FONT = "body_large"
-- The shadow: 25% less opaque than Helldivers Arcade's (192), and a third closer to the number.
M.SHADOW = { 0, 0, 0, 144 }
M.SHADOW_REACH = 2 / 3

-- How far the shadow sits from the number, in pixels, for a number `size` pixels tall.
function M.shadow_offset(size)
	return math.max(2, math.floor(size / 14)) * M.SHADOW_REACH
end

function M.draw_number(kit, text, x, y, size, ink)
	local base = kit:layer()
	local opts = { font = M.FONT, size = size, align = "center" }
	local d = M.shadow_offset(size)
	kit:layer(base - 1)
	opts.color = M.SHADOW
	kit:text(text, x + d, y - d, opts)
	kit:layer(base)
	opts.color = ink
	kit:text(text, x, y, opts)
end

local function track_players(list, opened, mode, now)
	for _, p in ipairs(api.game.all_avatars() or {}) do
		local ok, s = pcall(g("EntityAux").state, p.unit, "health")
		if ok and s and type(s.hitpoints) == "number" then
			local was = last_hp[p.unit]
			if was and s.hitpoints < was - 0.5 and not s.is_downed and not s.is_dead then
				M.add(list, opened, p.unit, was - s.hitpoints, "player", nil, mode, now)
			end
			last_hp[p.unit] = s.hitpoints
		end
	end
end

-- which(): "off", "enemies", "players" or "both". mode(): "stacked" or "accumulated".
-- position(): "entity", "bar" or "hit".
function M.install(which, mode, position)
	local kit = obsidian.ui.canvas("betterhud_numbers", { layer = 410 })
	local clock = 0
	local failed = false
	local function wants(kind)
		local w = which()
		return w == "both" or w == kind .. "s"
	end
	if api.combat and api.combat.on_hit then
		api.combat.on_hit(function(victim, hit)
			if not wants("enemy") or not g("EntityAux").has_component(victim, "enemy") then return end
			M.add(live, open, victim, hit.damage, "enemy", hit.position, mode(), clock)
		end)
	end
	obsidian.on_frame(function()
		local dt = rawget(_G, "ENGINE_DT") or 0.016
		clock = clock + dt
		if which() == "off" or not api.game.in_mission() or photo_mode() then
			if #live > 0 then
				for _, n in ipairs(live) do n.gone = true end
				live = {}
			end
			return
		end
		local ok, err = pcall(function()
			if wants("player") then track_players(live, open, mode(), clock) end
			M.step(live, clock)
			local st = api.game.state()
			local hud = st and st.hud
			if (hud and (hud.hidden or hud.enabled == false)) or (api.map.is_open and api.map.is_open()) then return end
			local scale = hud and hud.hd_gui and hud.hd_gui.ui_scale
			if not scale then
				local _, h = g("Application").resolution()
				scale = h / 720
			end
			local where = position()
			for _, n in ipairs(live) do
				local x, y, inside = screen_of(n, where, scale)
				if x and inside then
					local rise, alpha = M.look(n, clock)
					local ink = n.kind == "player" and PLAYER_INK or ENEMY_INK
					local spread = (where == "hit" and n.mode == "stacked") and n.jitter * scale or 0
					kit:opacity(alpha)
					M.draw_number(kit, tostring(math.floor(n.amount + 0.5)), x + spread, y + rise * M.RISE * scale, SIZE * scale, ink)
				end
			end
			kit:opacity(1)
		end)
		if not ok and not failed then
			failed = true
			obsidian.log("betterhud: damage numbers: " .. tostring(err))
		end
	end)
end

return M
