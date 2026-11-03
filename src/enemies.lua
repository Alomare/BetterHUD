-- Health bars over enemies, in the game's look: a bar over each damaged enemy (or each damaged heavy)
-- in its faction's colour, white chunks that fade out where health was lost, as the game's own bars
-- do, tinted orange while it burns and green while poisoned, a pulsing blue backing while stunned,
-- ticks every 100 health, a size by how much health it has, and a dark red flash when it dies.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
-- Sizes are in the HUD's design units, times the HUD's own scale, so they follow the UI scale setting.
-- Health is the replicated hitpoints of every enemy, so the bars show on every player's game.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local LINGER = 8 -- seconds a bar stays after the last loss
local FADE_IN, FADE_OUT = 0.15, 0.27
local DEATH_HOLD, DEATH_FADE = 0.5, 0.22
local CHUNK_LIFE, CHUNKS = 1, 5 -- a lost stretch fades out in this many seconds; this many at once
local LIMIT = 64
local TICK_HP = 100

-- By max health: width and height in HUD design units, and how high over the enemy's root when its
-- bounding box can't be read.
local TIERS = {
	{ hp = 0, w = 40, h = 4.1, lift = 2.2 },
	{ hp = 400, w = 53, h = 5.4, lift = 2.5 },
	{ hp = 1500, w = 67, h = 6.6, lift = 3.6 },
	{ hp = 5000, w = 80, h = 8.3, lift = 8.0 },
}
local LIFT = 13 -- design units between the anchor and the bar

local BACK = "#0d0d0d42"
local OUTLINE = "#00000063"
-- Health by faction.
local FACTIONS = { bugs = "#ff8c14e6", cyborgs = "#e1281ee6", illuminates = "#a046e6e6" }
local OTHER = "#ff3719e6"
local LAG = { 255, 255, 255 }
local FIRE = { 224, 148, 18 }
local POISON = { 89, 184, 38 }
local STUN = "#2666b3"
local TICK = "#00000033"
-- From, to (shares of the height from the bottom) and colour.
local SHADE = {
	{ 0, 0.2, "#00000038" }, { 0.2, 0.4, "#0000001a" },
	{ 0.6, 0.8, "#ffffff12" }, { 0.8, 1, "#ffffff2a" },
}
local DEATH = "#660505e6"

local tracked = {}
local heavy_of = setmetatable({}, { __mode = "k" })
local height_of = setmetatable({}, { __mode = "k" })

local function tier(max)
	local t = TIERS[1]
	for _, x in ipairs(TIERS) do
		if max >= x.hp then t = x end
	end
	return t
end

local function health(unit)
	local ok, s = pcall(g("EntityAux").state, unit, "health")
	return ok and s or nil
end

-- (hp + |constitution|) / (max + |constitution|): an enemy dies at its constitution, below 0, so the
-- bar is empty when it dies.
local function fraction(s)
	local pool = -(s.constitution or 0)
	local max = (s.max_hitpoints or 1) + pool
	return math.max(0, math.min(1, ((s.hitpoints or 0) + pool) / max))
end

local faction_of = setmetatable({}, { __mode = "k" })

local function enemy_of(unit)
	local ok, path = pcall(g("Unit").get_data, unit, "unit_path")
	return ok and path and api.catalog.enemy(path) or nil
end

local function colours(unit)
	local c = faction_of[unit]
	if c then return c end
	local e = enemy_of(unit)
	c = e and FACTIONS[e.faction] or OTHER
	faction_of[unit] = c
	return c
end

local function is_heavy(unit)
	local h = heavy_of[unit]
	if h ~= nil then return h end
	h = false
	local lsm = g("LuaSettingsManager")
	local ok, settings = pcall(lsm.get_settings_by_unit, lsm, unit)
	if ok and type(settings) == "table" then h = settings.heavy == true end
	local e = enemy_of(unit)
	if e and e.boss then h = true end
	heavy_of[unit] = h
	return h
end

-- How far over its root the bar sits: the top of its bounding box, read once.
local function top_of(unit, t)
	local z = height_of[unit]
	if z then return z end
	local ok, pose, extents = pcall(g("Unit").box, unit)
	if ok and pose and extents then
		local V3, M4 = g("Vector3"), g("Matrix4x4")
		local okt, at = pcall(M4.translation, pose)
		local root = g("Unit").world_position(unit, 0)
		if okt and at then z = V3.z(at) + V3.z(extents) - V3.z(root) + 0.4 end
	end
	z = z or t.lift
	height_of[unit] = z
	return z
end

local function status(unit, kind, name)
	local S = g("StatusComponent")
	local fn = S and S[kind]
	if not fn then return false end
	local ok, on = pcall(fn, unit, name)
	return ok and on == true
end

-- Each loss leaves a white chunk where the health was, fading out, as the game's own bars do
-- (hud.lua:461-476). A heal drops the chunks it covers.
local function chunks_step(b, pct, dt)
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
end

-- Every enemy that's lost health since it was first seen, as the filter allows.
local function follow(now, only_heavies)
	local seen = {}
	for _, unit in ipairs(api.enemies.list()) do
		seen[unit] = true
		local s = health(unit)
		local b = tracked[unit]
		if s and s.max_hitpoints and s.max_hitpoints > 0 then
			local pct = fraction(s)
			if not b and pct < 1 and (not only_heavies or is_heavy(unit)) then
				b = { unit = unit, pct = 1, chunks = {}, born = now, hit = now, max = s.max_hitpoints }
				tracked[unit] = b
			end
			if b and not b.dead then
				if pct < b.pct - 1e-4 then b.hit = now end
				b.now_pct = pct
				if s.is_dead or (s.hitpoints or 1) <= (s.constitution or 0) then b.dead = now end
			end
		end
	end
	for unit, b in pairs(tracked) do
		if not seen[unit] and not b.dead then b.dead = now end
	end
end

local function alpha_of(b, now)
	if b.dead then
		local t = now - b.dead
		if t < DEATH_HOLD then return 1 end
		return math.max(0, 1 - (t - DEATH_HOLD) / DEATH_FADE)
	end
	local a = math.min(1, (now - b.born) / FADE_IN)
	local idle = now - b.hit - LINGER
	if idle > 0 then a = a * math.max(0, 1 - idle / FADE_OUT) end
	return a
end

local function gone(b, now)
	if b.dead then return now - b.dead > DEATH_HOLD + DEATH_FADE end
	return now - b.hit > LINGER + FADE_OUT
end

local function rgba(c, a) return { c[1], c[2], c[3], math.floor(255 * a) } end

local function draw_bar(kit, b, now, scale)
	local unit = b.unit
	if not b.dead or now - b.dead < 0.05 then
		if g("Unit").alive(unit) then
			local at = g("Unit").world_position(unit, 0)
			local V3 = g("Vector3")
			b.anchor = { x = V3.x(at), y = V3.y(at), z = V3.z(at) + top_of(unit, tier(b.max)) }
		end
	end
	if not b.anchor then return end
	local sx, sy, inside = api.world.to_screen(b.anchor)
	if not sx or not inside then return end
	local t = tier(b.max)
	local w, h = t.w * scale, math.max(2, t.h * scale)
	local x, y = sx - w / 2, sy + LIFT * scale
	kit:opacity(alpha_of(b, now))
	if b.dead then
		kit:rect(x - 1, y - 1, w + 2, h + 2, OUTLINE)
		kit:rect(x, y, w, h, DEATH)
		return
	end
	local stunned = status(unit, "is_status_enabled", "stun") or status(unit, "is_element_enabled", "generic_stun")
	local back = BACK
	if stunned then
		local pulse = 0.5 - 0.5 * math.cos(2 * math.pi * now / 0.8)
		back = string.format("%s%02x", STUN, math.floor((0.6 + 0.1 * pulse) * 255))
	end
	kit:rect(x - 1, y - 1, w + 2, h + 2, OUTLINE)
	kit:rect(x, y, w, h, back)
	local pct = b.pct
	if #b.chunks > 0 then
		local tint = LAG
		if status(unit, "is_element_enabled", "fire") then tint = FIRE elseif status(unit, "is_element_enabled", "poison") then tint = POISON end
		for _, c in ipairs(b.chunks) do
			kit:rect(x + w * c.from, y, w * (c.to - c.from), h, rgba(tint, 0.85 * c.life / CHUNK_LIFE))
		end
	end
	-- The bar runs out where the enemy dies, its constitution counted in (see fraction).
	local s = health(unit)
	local pool = s and -(s.constitution or 0) or 0
	kit:rect(x, y, w * pct, h, colours(unit))
	-- A soft shade over the bar, light at the top and dark at the bottom, in bands (y is up).
	for _, band in ipairs(SHADE) do
		kit:rect(x, y + h * band[1], w, h * (band[2] - band[1]), band[3])
	end
	-- A tick every 100 health, or every 200, 500, 1000... until they're 5 pixels apart.
	local step = TICK_HP
	for _, k in ipairs({ 1, 2, 5, 10, 20, 50, 100 }) do
		step = TICK_HP * k
		if w * step / (b.max + pool) >= 5 then break end
	end
	local n = 1
	while step * n < b.max + pool do
		kit:rect(x + w * step * n / (b.max + pool) - 1, y, 2, h, TICK)
		n = n + 1
	end
end

function M.install(active, only_heavies)
	local kit = obsidian.ui.canvas("betterhud_enemies", { layer = 400 })
	local clock = 0
	local failed = false
	obsidian.on_frame(function()
		local dt = rawget(_G, "ENGINE_DT") or 0.016
		clock = clock + dt
		if not active() or not api.game.in_mission() then
			if next(tracked) then tracked = {} end
			return
		end
		local ok, err = pcall(function()
			local st = api.game.state()
			local hud = st and st.hud
			follow(clock, only_heavies())
			local list = {}
			for unit, b in pairs(tracked) do
				if gone(b, clock) then tracked[unit] = nil else
					if b.now_pct then chunks_step(b, b.now_pct, dt) end
					list[#list + 1] = b
				end
			end
			if (hud and (hud.hidden or hud.enabled == false)) or (api.map.is_open and api.map.is_open()) then return end
			table.sort(list, function(a, b) return a.hit > b.hit end)
			-- Pixels a design unit: the HUD's own scale, the player's UI scale setting in it.
			local scale = hud and hud.hd_gui and hud.hd_gui.ui_scale
			if not scale then
				local _, h = g("Application").resolution()
				scale = h / 720
			end
			for i = math.min(#list, LIMIT), 1, -1 do draw_bar(kit, list[i], clock, scale) end
			kit:opacity(1)
		end)
		if not ok and not failed then
			failed = true
			obsidian.log("betterhud: enemy bars: " .. tostring(err))
		end
	end)
end

return M
