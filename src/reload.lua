-- A ring over the player's Helldiver that fills while the weapon in hand reloads. Each weapon component
-- that reloads counts reload_time down from reload_duration in the master state, which this machine
-- holds for its own player, and leaves reload_time below zero when it isn't reloading.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local KINDS = { "firearm", "flameweapon", "launcher", "beamweapon", "arcweapon" }
local HEAD = 1.9 -- metres over the feet
local ABOVE = 34 -- design units over the head
local RADIUS, WIDTH = 11, 3.5 -- design units
local EDGE = 1.5 -- design units of dark border around the track
local SEGMENTS = 40
local TRACK, BORDER = { 30, 30, 30, 170 }, { 0, 0, 0, 200 }
local FILL, LIT = { 255, 200, 60, 255 }, { 255, 236, 160, 255 }

-- How far the reload has come, from 0 to 1, or nil when the weapon isn't reloading.
function M.progress(state)
	local left, total = state.reload_time, state.reload_duration
	if type(left) ~= "number" or type(total) ~= "number" or left < 0 or total <= 0 then return nil end
	if state.is_reloading == false then return nil end
	return math.max(0, math.min(1, 1 - left / total))
end

local function weapon_progress(unit)
	local inv = g("EntityAux").state(unit, "inventory")
	local weapon = inv and inv.current_weapon
	if not weapon then return nil end
	for _, kind in ipairs(KINDS) do
		local state = api.game.master(weapon, kind)
		if state then return M.progress(state) end
	end
	return nil
end

-- A band of the ring from angle a to b (radians, clockwise from the top), as one convex quad.
local function arc(kit, x, y, r1, r2, a, b, color)
	local s1, c1, s2, c2 = math.sin(a), math.cos(a), math.sin(b), math.cos(b)
	kit:poly({ x + s1 * r1, y + c1 * r1, x + s1 * r2, y + c1 * r2, x + s2 * r2, y + c2 * r2, x + s2 * r1, y + c2 * r1 }, color)
end

local function ring(kit, x, y, r1, r2, from, to, color)
	local step = 2 * math.pi / SEGMENTS
	local a = from
	while a < to - 1e-6 do
		local b = math.min(to, a + step)
		arc(kit, x, y, r1, r2, a, b, color)
		a = b
	end
end

function M.draw(kit, x, y, p, scale)
	local r2 = RADIUS * scale
	local r1 = r2 - WIDTH * scale
	local e = EDGE * scale
	kit:layer(419)
	ring(kit, x, y, r1 - e, r2 + e, 0, 2 * math.pi, BORDER)
	kit:layer(420)
	ring(kit, x, y, r1, r2, 0, 2 * math.pi, TRACK)
	if p > 0 then
		kit:layer(421)
		ring(kit, x, y, r1, r2, 0, 2 * math.pi * p, FILL)
		-- A lighter inner half of the filled band, so the ring reads as shaded rather than flat.
		kit:layer(422)
		ring(kit, x, y, r1 + (r2 - r1) * 0.5, r2, 0, 2 * math.pi * p, LIT)
	end
end

function M.install(active)
	local kit = obsidian.ui.canvas("betterhud_reload", { layer = 420 })
	local failed = false
	obsidian.on_frame(function()
		if not active() or not api.game.in_mission() then return end
		local ok, err = pcall(function()
			local unit = api.game.my_unit()
			if not unit then return end
			local p = weapon_progress(unit)
			if not p then return end
			local st = api.game.state()
			local hud = st and st.hud
			if (hud and (hud.hidden or hud.enabled == false)) or (api.map.is_open and api.map.is_open()) then return end
			local at = g("Unit").world_position(unit, 0)
			local V3 = g("Vector3")
			local x, y, inside = api.world.to_screen({ x = V3.x(at), y = V3.y(at), z = V3.z(at) + HEAD })
			if not (x and inside) then return end
			local scale = hud and hud.hd_gui and hud.hd_gui.ui_scale
			if not scale then
				local _, h = g("Application").resolution()
				scale = h / 720
			end
			M.draw(kit, x, y + ABOVE * scale, p, scale)
		end)
		if not ok and not failed then
			failed = true
			obsidian.log("betterhud: reload circle: " .. tostring(err))
		end
	end)
end

return M
