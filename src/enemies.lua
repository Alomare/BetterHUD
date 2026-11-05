-- Health bars over enemies, in the game's look: a bar over each enemy a player of this machine has hit
-- (Obsidian API's combat.on_hit, 1.14.0) and each heavy anyone has hurt, in the faction's colour. A white
-- stretch shows the health lost since the hits began: each hit renews it, and it fades out all at once
-- LAG_HOLD seconds after the last. A pulsing outline shows a burn (orange), poison (green) or stun (blue);
-- the size follows the enemy's health, and a white flash marks a death. The bar of an enemy out of view
-- waits on the screen's edge, EDGE design units in, on the side the enemy is.
-- With an older API, every damaged enemy gets a bar.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
-- Sizes are in the HUD's design units, times the HUD's own scale, so they follow the UI scale setting.
-- Health is the replicated hitpoints of every enemy, so the bars show on every player's game.
local api = obsidian.import("obsidian.api")

-- Photo Mode (or any mod) clearing the screen for pictures through Obsidian API's photo effect.
local function photo_mode()
	local effects = api.effects
	return effects ~= nil and effects.is_on ~= nil and effects.is_on("photo_mode") == true
end

local M = {}

local function g(name) return rawget(_G, name) end

local LINGER = 8 -- seconds a bar stays after the last loss
local FADE_IN, FADE_OUT = 0.15, 0.27
local DEATH_HOLD, DEATH_FADE = 0.5, 0.11
-- The white stretch of lost health: seconds at full strength after the last hit, then seconds to fade.
M.LAG_HOLD, M.LAG_FADE = 0.5, 0.35
local LAG_ALPHA = 0.85
local LIMIT = 64
M.OPACITY = 0.85 -- of the whole bar
M.EDGE = 8 -- design units between the screen's edge and a bar held there

-- By max health: width and height in HUD design units, and how high over the enemy's root when its
-- bounding box can't be read.
local TIERS = {
	{ hp = 0, w = 40, h = 4.1, lift = 2.2 },
	{ hp = 400, w = 53, h = 5.4, lift = 2.5 },
	{ hp = 1500, w = 67, h = 6.6, lift = 3.6 },
	{ hp = 5000, w = 80, h = 8.3, lift = 8.0 },
}
M.TIERS = TIERS
local LIFT = 13 -- design units between the anchor and the bar

local BACK = "#0d0d0d42"
local OUTLINE = "#00000063"
M.OUTLINE_PX = 2 -- the black outline around a bar, in pixels
-- Health by faction.
local FACTIONS = { bugs = "#ff8c14e6", cyborgs = "#e1281ee6", illuminates = "#a046e6e6" }
local OTHER = "#ff3719e6"
local LAG = { 255, 255, 255 }
-- Status outlines, pulsing, in design units of thickness.
local FIRE, POISON, STUN = { 255, 150, 20 }, { 110, 210, 50 }, { 60, 140, 255 }
local RING = 1.6
-- From, to (shares of the height from the bottom) and colour.
local SHADE = {
	{ 0, 0.2, "#00000038" }, { 0.2, 0.4, "#0000001a" },
	{ 0.6, 0.8, "#ffffff12" }, { 0.8, 1, "#ffffff2a" },
}
local DEATH = "#ffffffeb"

local tracked = {}
-- Enemies a player of this machine has hit, by when: they get a bar however much health they lost.
local hit_by_me = setmetatable({}, { __mode = "k" })
local hits_known = false
-- Where each bar was drawn this frame, on screen, for damage numbers over it.
M.drawn = {}
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

-- How strong the white stretch is at `now`, from 0 to 1.
function M.lag_alpha(lag, now)
	if not lag then return 0 end
	local idle = now - lag.hit
	if idle <= M.LAG_HOLD then return 1 end
	return math.max(0, 1 - (idle - M.LAG_HOLD) / M.LAG_FADE)
end

-- One white stretch for every loss, from the health now up to where it stood before the hits began. A
-- loss while the stretch shows (or fades) renews it at full strength and keeps its top; it fades once
-- LAG_HOLD seconds pass without one. A heal past the top drops it. b: { pct, lag }.
function M.lag_step(b, pct, now)
	local lag = b.lag
	if lag and (M.lag_alpha(lag, now) <= 0 or pct >= lag.top - 1e-4) then
		lag = nil
	end
	if pct < b.pct - 1e-4 then
		if lag then lag.hit = now else lag = { top = b.pct, hit = now } end
	end
	b.lag = lag
	b.pct = pct
end

-- Where a bar w by h, its bottom left at x, y on a screen sw by sh, goes when its enemy is out of view:
-- the nearest spot with `gap` pixels between the bar and each edge. Answers the bottom left.
function M.pin(x, y, w, h, sw, sh, gap)
	local function fit(v, size, room)
		local lo, hi = gap, room - gap - size
		if hi < lo then return (room - size) / 2 end
		return math.max(lo, math.min(hi, v))
	end
	return fit(x, w, sw), fit(y, h, sh)
end

-- Whether a point of the level is behind the camera, where the screen position mirrors.
local function behind(anchor)
	local cam, V3 = g("CameraManager"), g("Vector3")
	if not (cam and V3 and cam.world_to_screen) then return false end
	local ok, s = pcall(cam.world_to_screen, cam, V3(anchor.x, anchor.y, anchor.z))
	return ok and s ~= nil and s.z <= 0
end

-- Every enemy that's lost health since it was first seen: hit by this machine's player, or a heavy.
local function wanted(unit)
	if not hits_known then return true end
	return hit_by_me[unit] ~= nil or is_heavy(unit)
end

local function follow(now)
	local seen = {}
	for _, unit in ipairs(api.enemies.list()) do
		seen[unit] = true
		local s = health(unit)
		local b = tracked[unit]
		if s and s.max_hitpoints and s.max_hitpoints > 0 then
			local pct = fraction(s)
			if not b and pct < 1 and wanted(unit) then
				b = { unit = unit, pct = 1, born = now, hit = now, max = s.max_hitpoints }
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

-- Status build-up another mod reports (M.buildup): unit -> { kind -> fraction }. Each kind is a thin
-- strip along the bottom edge of the bar's outline, filling from the left in the status's color, in
-- this order, one under the other.
M.BUILDUP_KINDS = { "fire", "poison", "stun" }
local BUILDUP_COLOR = { fire = FIRE, poison = POISON, stun = STUN }
local buildups = {}

-- obsidian.import("alomare.betterhud").status_buildup(unit, kind, fraction): how far a status has built
-- up on an enemy, 0 to 1, shown under the enemy's health bar; nil clears it. kind: "fire", "poison" or
-- "stun". Entries of units that are gone are dropped.
function M.buildup(unit, kind, fraction)
	if unit == nil or not BUILDUP_COLOR[kind] then return false end
	if fraction ~= nil and type(fraction) ~= "number" then return false end
	local U = g("Unit")
	for u in pairs(buildups) do
		local ok, alive = pcall(U.alive, u)
		if not (ok and alive) then buildups[u] = nil end
	end
	local by = buildups[unit]
	if fraction == nil or fraction <= 0 then
		if by then
			by[kind] = nil
			if next(by) == nil then buildups[unit] = nil end
		end
		return true
	end
	by = by or {}
	buildups[unit] = by
	by[kind] = math.min(1, fraction)
	return true
end

function M.buildup_of(unit, kind)
	return buildups[unit] and buildups[unit][kind] or nil
end

local function draw_buildup(kit, unit, x, y, w)
	local by = buildups[unit]
	if not by then return end
	local o = M.OUTLINE_PX
	local strip = math.max(2, o)
	local at = y - o
	for _, kind in ipairs(M.BUILDUP_KINDS) do
		local f = by[kind]
		if f then
			kit:rect(x - o, at, (w + 2 * o) * f, strip, rgba(BUILDUP_COLOR[kind], 0.95))
			at = at - strip
		end
	end
end

-- Effects another mod reports (M.effect): unit -> { kind -> { start, ends, icon } }. While one runs, its
-- icon shows over the enemy's health bar with a soft dark outline, fading in fast when it starts and
-- out as it ends. Several run side by side, in BUILDUP_KINDS order.
M.now = 0
local effects = {}
M.ICON = 20 -- design units across
M.ICON_IN, M.ICON_OUT = 0.12, 0.3 -- seconds of the fades
local ICON_GAP = 3 -- design units between icons, and above the bar
local HALO = { 0, 0, 0 }

-- The icon's opacity `now`, for an effect that started at `start` and ends at `ends`.
function M.effect_alpha(start, ends, now)
	if now >= ends or now < start then return 0 end
	return math.min(1, (now - start) / M.ICON_IN, (ends - now) / M.ICON_OUT)
end

-- obsidian.import("alomare.betterhud").status_effect(unit, kind, seconds, icon): an effect runs on an
-- enemy for `seconds` from now (0 or nil ends it), with `icon` over its health bar: { art = material, uv
-- = { u0, v0, u1, v1 } } for an image a mod ships, or { icon = name } for one of the game's. kind:
-- "fire", "poison" or "stun". Called again while it runs, it runs longer and doesn't fade in again.
function M.effect(unit, kind, seconds, icon)
	if unit == nil or not BUILDUP_COLOR[kind] then return false end
	local U = g("Unit")
	for u in pairs(effects) do
		local ok, alive = pcall(U.alive, u)
		if not (ok and alive) then effects[u] = nil end
	end
	local now = M.now
	local by = effects[unit] or {}
	if not (tonumber(seconds) and seconds > 0) then
		by[kind] = nil
		if next(by) == nil then effects[unit] = nil else effects[unit] = by end
		return true
	end
	if type(icon) ~= "table" or not (icon.art or icon.icon) then return false end
	local e = by[kind]
	local running = e and now < e.ends
	by[kind] = { start = running and e.start or now, ends = now + math.min(seconds, 60), icon = icon }
	effects[unit] = by
	return true
end

function M.effect_of(unit, kind)
	return effects[unit] and effects[unit][kind] or nil
end

local function icon_at(kit, spec, x, y, s, c)
	if spec.art then return kit:art(spec.art, x, y, s, s, c, spec.uv) end
	return kit:icon(spec.icon, x, y, s, s, c)
end

local function draw_effects(kit, unit, cx, top, now, scale)
	local by = effects[unit]
	if not by then return end
	local shown = {}
	for _, kind in ipairs(M.BUILDUP_KINDS) do
		local e = by[kind]
		if e then
			local a = M.effect_alpha(e.start, e.ends, now)
			if a > 0 then shown[#shown + 1] = { e = e, a = a } elseif now >= e.ends then by[kind] = nil end
		end
	end
	if #shown == 0 then return end
	local s, gap = M.ICON * scale, ICON_GAP * scale
	local x = cx - (#shown * s + (#shown - 1) * gap) / 2
	local y = top + gap
	local d = math.max(1, 1.5 * scale)
	for _, item in ipairs(shown) do
		-- The soft outline: the icon in black, a little off to each side, faint.
		local halo = rgba(HALO, 0.35 * item.a)
		for _, o in ipairs({ { -d, 0 }, { d, 0 }, { 0, -d }, { 0, d }, { -d, -d }, { d, -d }, { -d, d }, { d, d } }) do
			icon_at(kit, item.e.icon, x + o[1], y + o[2], s, halo)
		end
		icon_at(kit, item.e.icon, x, y, s, rgba({ 255, 255, 255 }, item.a))
		x = x + s + gap
	end
end

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
	if not sx then return end
	local t = tier(b.max)
	local w, h = t.w * scale, math.max(2, t.h * scale)
	local x, y = sx - w / 2, sy + LIFT * scale
	if not inside then
		-- Out of view: held on the nearest edge, clear of it by EDGE and the status outline.
		if behind(b.anchor) then return end
		local sw, sh = g("Application").resolution()
		local margin = M.EDGE * scale + math.max(2, RING * scale) + M.OUTLINE_PX
		x, y = M.pin(x, y, w, h, sw, sh, margin)
	end
	kit:opacity(alpha_of(b, now) * M.OPACITY)
	M.drawn[unit] = { x = x + w / 2, y = y + h, pinned = not inside }
	if b.dead then
		kit:rect(x - M.OUTLINE_PX, y - M.OUTLINE_PX, w + 2 * M.OUTLINE_PX, h + 2 * M.OUTLINE_PX, OUTLINE)
		kit:rect(x, y, w, h, DEATH)
		return
	end
	-- A status shows as a pulsing outline around the whole bar.
	local ring
	if status(unit, "is_element_enabled", "fire") then ring = FIRE
	elseif status(unit, "is_element_enabled", "poison") then ring = POISON
	elseif status(unit, "is_status_enabled", "stun") or status(unit, "is_element_enabled", "generic_stun") then ring = STUN end
	if ring then
		local pulse = 0.5 - 0.5 * math.cos(2 * math.pi * now / 0.7)
		local r, c = math.max(2, RING * scale), rgba(ring, 0.45 + 0.45 * pulse)
		local o = M.OUTLINE_PX
		local left, bottom, ow, oh = x - o - r, y - o - r, w + 2 * o + r * 2, h + 2 * o + r * 2
		kit:rect(left, bottom, ow, r, c)
		kit:rect(left, bottom + oh - r, ow, r, c)
		kit:rect(left, bottom + r, r, oh - r * 2, c)
		kit:rect(left + ow - r, bottom + r, r, oh - r * 2, c)
	end
	kit:rect(x - M.OUTLINE_PX, y - M.OUTLINE_PX, w + 2 * M.OUTLINE_PX, h + 2 * M.OUTLINE_PX, OUTLINE)
	kit:rect(x, y, w, h, BACK)
	local pct = b.pct
	local lag = M.lag_alpha(b.lag, now)
	if lag > 0 then
		kit:rect(x + w * pct, y, w * (b.lag.top - pct), h, rgba(LAG, LAG_ALPHA * lag))
	end
	-- The bar runs out where the enemy dies, its constitution counted in (see fraction).
	kit:rect(x, y, w * pct, h, colours(unit))
	-- A soft shade over the bar, light at the top and dark at the bottom, in bands (y is up).
	for _, band in ipairs(SHADE) do
		kit:rect(x, y + h * band[1], w, h * (band[2] - band[1]), band[3])
	end
	draw_buildup(kit, unit, x, y, w)
	-- Clear of the status outline's ring, which pulses around the bar while a status is on.
	draw_effects(kit, unit, x + w / 2, y + h + M.OUTLINE_PX + math.max(2, RING * scale), now, scale)
end

-- The top of an enemy, in the level: where damage numbers sit next to it.
function M.anchor_of(unit)
	if not g("Unit").alive(unit) then return nil end
	local at, V3 = g("Unit").world_position(unit, 0), g("Vector3")
	local s = health(unit)
	return { x = V3.x(at), y = V3.y(at), z = V3.z(at) + top_of(unit, tier(s and s.max_hitpoints or 1)) }
end

function M.install(active)
	local kit = obsidian.ui.canvas("betterhud_enemies", { layer = 400 })
	local clock = 0
	local failed = false
	if api.combat and api.combat.on_hit then
		hits_known = api.combat.on_hit(function(victim)
			if g("EntityAux").has_component(victim, "enemy") then hit_by_me[victim] = clock end
		end) == true
	end
	obsidian.on_frame(function()
		local dt = rawget(_G, "ENGINE_DT") or 0.016
		clock = clock + dt
		M.now = clock
		if not active() or not api.game.in_mission() or photo_mode() then
			if next(tracked) then tracked = {} end
			return
		end
		local ok, err = pcall(function()
			local st = api.game.state()
			local hud = st and st.hud
			M.drawn = {}
			follow(clock)
			local list = {}
			for unit, b in pairs(tracked) do
				if gone(b, clock) then tracked[unit] = nil else
					if b.now_pct then M.lag_step(b, b.now_pct, clock) end
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
