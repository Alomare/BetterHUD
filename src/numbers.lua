-- Damage numbers: a number where damage lands, rising a little and fading out. Damage to enemies is what
-- this machine's players deal (Obsidian API's combat.on_hit, 1.14.0); damage to players is what their
-- replicated health loses. Stacked: a number for each hit. Accumulated: hits on one target less than
-- WINDOW seconds apart add up into one number, which then rises and fades.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
local api = obsidian.import("obsidian.api")
local enemies = obsidian.module("src/enemies")

local M = {}

local function g(name) return rawget(_G, name) end

M.WINDOW = 0.3 -- seconds between hits that still add up
local LIFE, RISE = 0.9, 26 -- seconds a number lasts once released; design units it climbs
local SIZE = 15 -- design units
local SIDE = 16 -- design units right of the entity, for "next to the entity"
local LIMIT = 48
local ENEMY_INK, PLAYER_INK = { 236, 236, 236 }, { 255, 95, 75 }

local live = {}
local open = setmetatable({}, { __mode = "k" })
local last_hp = setmetatable({}, { __mode = "k" })

-- A new hit on `unit` worth `amount` at time `now`. kind: "enemy" or "player". at: where it landed, or nil.
-- mode: "stacked" or "accumulated". Answers the number it went into.
function M.add(list, opened, unit, amount, kind, at, mode, now)
	if amount <= 0 then return nil end
	if mode == "accumulated" then
		local n = opened[unit]
		if n and not n.released and now - n.last <= M.WINDOW then
			n.amount, n.last = n.amount + amount, now
			return n
		end
	end
	local n = { unit = unit, amount = amount, kind = kind, at = at, born = now, last = now, released = mode ~= "accumulated" and now or nil,
		jitter = (#list % 5 - 2) * 6 }
	list[#list + 1] = n
	if mode == "accumulated" then opened[unit] = n end
	while #list > LIMIT do table.remove(list, 1) end
	return n
end

-- Lets accumulated numbers go once no hit has added to them for WINDOW seconds, and drops the finished.
function M.step(list, now)
	for i = #list, 1, -1 do
		local n = list[i]
		if not n.released and now - n.last > M.WINDOW then n.released = now end
		if n.released and now - n.released >= LIFE then table.remove(list, i) end
	end
end

-- How far it has risen (0 to 1) and how visible it is.
function M.look(n, now)
	if not n.released then return 0, 1 end
	local f = math.min(1, (now - n.released) / LIFE)
	local rise = 1 - (1 - f) * (1 - f)
	local alpha = f < 0.45 and 1 or math.max(0, 1 - (f - 0.45) / 0.55)
	return rise, alpha
end

local function screen_of(n, position, scale)
	if position == "hit" and n.at then
		local x, y, inside = api.world.to_screen(n.at)
		return x, y, inside
	end
	if position == "bar" then
		local spot = enemies.drawn[n.unit]
		if spot then return spot.x, spot.y + 4 * scale, true end
	end
	local anchor = enemies.anchor_of(n.unit) or n.anchor
	if not anchor then return nil end
	n.anchor = anchor
	local x, y, inside = api.world.to_screen(anchor)
	if not x then return nil end
	return x + SIDE * scale, y, inside
end

-- A number with a soft drop shadow and a dark outline under it, so it stays readable on snow, sand
-- and explosions. The kit draws text one layer over its own, so each pass sits on the layer below the
-- next: shadow, then outline, then the number.
local SHADOW, OUTLINE = { 0, 0, 0, 140 }, { 10, 10, 10, 235 }
local AROUND = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }

function M.draw_number(kit, text, x, y, size, ink, scale)
	local base = kit:layer()
	local opts = { font = "ui_heading", size = size, align = "center" }
	kit:layer(base - 2)
	opts.color = SHADOW
	kit:text(text, x + 1.8 * scale, y - 2.2 * scale, opts)
	kit:layer(base - 1)
	opts.color = OUTLINE
	local d = 1.3 * scale
	for _, o in ipairs(AROUND) do kit:text(text, x + o[1] * d, y + o[2] * d, opts) end
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

-- which(): "off", "enemies", "players" or "both". mode(): "off", "stacked" or "accumulated".
-- position(): "entity", "bar" or "hit".
function M.install(which, mode, position)
	local kit = obsidian.ui.canvas("betterhud_numbers", { layer = 410 })
	local clock = 0
	local failed = false
	local function wants(kind)
		local w = which()
		return mode() ~= "off" and (w == "both" or w == kind .. "s")
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
		if mode() == "off" or which() == "off" or not api.game.in_mission() then
			if #live > 0 then live = {} end
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
					kit:opacity(alpha)
					M.draw_number(kit, tostring(math.floor(n.amount + 0.5)), x + n.jitter * scale * (where == "hit" and 1 or 0), y + rise * RISE * scale,
						SIZE * scale, ink, scale)
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
