-- A ring beside each local player's Helldiver that fills while the weapon in hand reloads, and in the same
-- spot the ammo circle (src/ammo_circle.lua). Each weapon component that reloads counts reload_time down
-- from reload_duration in the master state, which this machine holds for its own players, and leaves
-- reload_time below zero when it isn't reloading.
--
-- The two never show at once: while the weapon reloads, and while a finished reload ring grows and fades,
-- the reload ring has the spot. A finished reload hides the ammo circle until the next shot. With the
-- reload circle off, the ammo circle still steps aside while the weapon reloads, since the magazine it
-- shows is on the way out.
--
-- Both rings sit to the left of the Helldiver, a little over the chest, in one color each, with a soft
-- shadow that is darkest at the bottom left and clears toward the top right.
--
-- Drawn on a kit with no frame, in screen pixels from the bottom left, as api.world.to_screen answers.
-- Sizes are in the HUD's design units at 100% UI scale, times the HUD's scale: the resolution's scale
-- times the UI scale setting (hd_gui.lua:27-32, SaveManager "ui_scale", 0.75 to 1).
local api = obsidian.import("obsidian.api")

-- Photo Mode (or any mod) clearing the screen for pictures through Obsidian API's photo effect.
local function photo_mode()
	local effects = api.effects
	return effects ~= nil and effects.is_on ~= nil and effects.is_on("photo_mode") == true
end
local ammo_circle = obsidian.module("src/ammo_circle")

local M = {}

local function g(name) return rawget(_G, name) end

local KINDS = { "firearm", "flameweapon", "launcher", "beamweapon", "arcweapon" }
local CHEST = 1.0 -- metres over the feet
M.LEFT = 42 -- design units left of the Helldiver
M.UP = 8 -- design units over the chest
local RADIUS, WIDTH = 11, 3.5 -- design units
local EDGE = 1.5 -- design units of dark border around the track
local SEGMENTS = 64
local TRACK, BORDER = { 30, 30, 30, 85 }, { 0, 0, 0, 100 }
local FILL = { 212, 212, 212, 255 }
-- The shadow: how much darker the fill gets at the bottom left, clearing toward the top right.
M.SHADOW = 0.35
-- The dividers between segments of the ammo circle: thin, see-through dark lines across the band.
local DIVIDER, DIVIDER_WIDTH = { 0, 0, 0, 120 }, 0.5 -- color; design units across, at least a pixel
local DONE = 0.1 -- seconds a finished ring takes to grow and fade out
local GROW = 0.45 -- how much bigger it ends, of its size
local NEAR_END = 0.85 -- a reload that stops past this far counts as finished, not cancelled
local BUTTON = 0.9 -- of the hole inside the ring, across, for the reload button

-- How far the reload has come, from 0 to 1, or nil when the weapon isn't reloading.
function M.progress(state)
	local left, total = state.reload_time, state.reload_duration
	if type(left) ~= "number" or type(total) ~= "number" or left < 0 or total <= 0 then return nil end
	if state.is_reloading == false then return nil end
	return math.max(0, math.min(1, 1 - left / total))
end

-- The weapon in hand, the master state of the component that fires it, and that component's kind.
local function weapon_state(unit)
	local inv = g("EntityAux").state(unit, "inventory")
	local weapon = inv and inv.current_weapon
	if not weapon then return nil end
	for _, kind in ipairs(KINDS) do
		local state = api.game.master(weapon, kind)
		if state then return weapon, state, kind end
	end
	return weapon, nil
end

-- A band of the ring from angle a to b (radians, clockwise from the top), as one convex quad.
local function arc(kit, x, y, r1, r2, a, b, color)
	local s1, c1, s2, c2 = math.sin(a), math.cos(a), math.sin(b), math.cos(b)
	kit:poly({ x + s1 * r1, y + c1 * r1, x + s1 * r2, y + c1 * r2, x + s2 * r2, y + c2 * r2, x + s2 * r1, y + c2 * r1 }, color)
end

-- How dark the shadow is at angle `a` (clockwise from the top), from 0 at the top right to 1 at the
-- bottom left.
function M.shadow_at(a)
	return (1 - (math.sin(a) + math.cos(a)) / math.sqrt(2)) / 2
end

-- `color` darkened by the shadow at angle `a`.
function M.shaded(color, a)
	local k = 1 - M.SHADOW * M.shadow_at(a)
	return { math.floor(color[1] * k + 0.5), math.floor(color[2] * k + 0.5), math.floor(color[3] * k + 0.5), color[4] }
end

-- A band from angle `from` to `to`, in pieces of at most 1/SEGMENTS of a turn; with `shade`, each piece
-- darkened by the shadow at its middle.
local function ring(kit, x, y, r1, r2, from, to, color, shade)
	local step = 2 * math.pi / SEGMENTS
	local a = from
	while a < to - 1e-6 do
		local b = math.min(to, a + step)
		arc(kit, x, y, r1, r2, a, b, shade and M.shaded(color, (a + b) / 2) or color)
		a = b
	end
end

-- A thin line across the band at angle `a`, `half` pixels to each side.
local function divider(kit, x, y, r1, r2, a, half, color)
	local s, c = math.sin(a), math.cos(a)
	local tx, ty = c * half, -s * half
	kit:poly({ x + s * r1 - tx, y + c * r1 - ty, x + s * r2 - tx, y + c * r2 - ty,
		x + s * r2 + tx, y + c * r2 + ty, x + s * r1 + tx, y + c * r1 + ty }, color)
end

-- Pixels a design unit: the resolution's scale times the UI scale setting.
function M.scale(gui, save, w, h)
	local res = gui and gui.ui_scale_resolution or math.min(w / 1280, h / 720)
	local user = gui and gui.ui_scale_user
	if not user and save then
		local ok, v = pcall(save.get, save, "ui_scale")
		user = ok and tonumber(v) or nil
	end
	return res * (user or 1)
end

-- How big and how visible a finished ring is, `t` seconds after it finished, or nil once gone.
function M.finish(t)
	if t >= DONE then return nil end
	local f = t / DONE
	return 1 + GROW * f, 1 - f
end

-- The radius inside the ring's band, in pixels, for a scale.
function M.inner_radius(scale)
	return (RADIUS - WIDTH) * scale
end

-- Where the dividers go for a magazine of `size`: the angles (clockwise from the top) between segments.
function M.divider_angles(size)
	local step, count = ammo_circle.segments(size)
	if not step then return {} end
	size = math.floor(size)
	local out = {}
	for i = 1, count - 1 do out[i] = 2 * math.pi * i * step / size end
	-- The top, where the first segment starts and the last ends.
	out[#out + 1] = 0
	return out
end

-- The ring, filled `p` of the way round from the top, clockwise, or counter-clockwise with look.ccw.
-- look: { fill, track, ccw, size }, or nil for the reload ring's grey; size: the magazine's size, for
-- a divider between each segment.
function M.draw(kit, x, y, p, scale, look)
	local r2 = RADIUS * scale
	local r1 = r2 - WIDTH * scale
	local e = EDGE * scale
	kit:layer(419)
	ring(kit, x, y, r1 - e, r2 + e, 0, 2 * math.pi, BORDER)
	kit:layer(420)
	ring(kit, x, y, r1, r2, 0, 2 * math.pi, look and look.track or TRACK)
	if p > 0 then
		kit:layer(421)
		local from, to = 0, 2 * math.pi * p
		if look and look.ccw then from, to = 2 * math.pi * (1 - p), 2 * math.pi end
		ring(kit, x, y, r1, r2, from, to, look and look.fill or FILL, true)
	end
	if look and look.size then
		kit:layer(422)
		local half = math.max(1, DIVIDER_WIDTH * scale) / 2
		for _, a in ipairs(M.divider_angles(look.size)) do divider(kit, x, y, r1, r2, a, half, DIVIDER) end
	end
end

-- The Helldivers of the people playing on this machine: the first player and any local co-op players,
-- whose weapons this machine runs, each with a pad number (nil for the first player, whose device is
-- the main one). Bots made through Obsidian API are left out.
local function local_players()
	local bots = {}
	if api.bots and api.bots.all then
		for _, b in ipairs(api.bots.all()) do
			local u = b:unit()
			if u then bots[u] = true end
		end
	end
	local out = {}
	for _, p in ipairs(api.game.all_avatars() or {}) do
		if p.owned and not bots[p.unit] then
			local pad = nil
			if #out > 0 and type(p.record) == "table" and type(p.record.pad_number) == "number" then pad = p.record.pad_number end
			out[#out + 1] = { unit = p.unit, pad = pad }
		end
	end
	return out
end

local last = setmetatable({}, { __mode = "k" }) -- unit: the progress drawn last frame
local done = setmetatable({}, { __mode = "k" }) -- unit: when its reload finished
local shots = setmetatable({}, { __mode = "k" }) -- unit: the ammo circle's tracking (src/ammo_circle.lua)

-- reload_on(), ammo_on(): whether the reload circle and the ammo circle show.
function M.install(reload_on, ammo_on)
	local kit = obsidian.ui.canvas("betterhud_reload", { layer = 420 })
	local failed = false
	local clock = 0
	obsidian.on_frame(function()
		clock = clock + (rawget(_G, "ENGINE_DT") or 0.016)
		local show_reload, show_ammo = reload_on(), ammo_on()
		if not (show_reload or show_ammo) or not api.game.in_mission() or photo_mode() then return end
		local ok, err = pcall(function()
			local st = api.game.state()
			local hud = st and st.hud
			local hidden = (hud and (hud.hidden or hud.enabled == false)) or (api.map.is_open and api.map.is_open())
			local w, h = g("Application").resolution()
			local scale = M.scale(hud and hud.hd_gui, g("SaveManager"), w, h)
			local V3 = g("Vector3")
			for _, player in ipairs(local_players()) do
				local unit = player.unit
				local weapon, state, kind = weapon_state(unit)
				local p = state and M.progress(state)
				local reloading = p ~= nil
				local was = last[unit]
				last[unit] = p
				-- The ammo circle follows every shot, shown or not, so it fades on time.
				local t = shots[unit]
				if not t then
					t = {}
					shots[unit] = t
				end
				if p then
					done[unit] = nil
				elseif was and was >= NEAR_END then
					done[unit] = clock
					ammo_circle.reloaded(t)
				end
				local grow, alpha = 1, 1
				if not p and done[unit] then
					grow, alpha = M.finish(clock - done[unit])
					if grow then p = 1 else done[unit] = nil end
				end
				if not show_reload then p = nil end
				local share, rounds, empty, size, ready = ammo_circle.reading(state)
				if share then ammo_circle.track(t, weapon, share, clock, reloading) end
				local ammo_alpha = (show_ammo and share and not reloading and not p) and ammo_circle.alpha(t.shot, clock) or 0
				if not hidden and (p or ammo_alpha > 0) then
					local at = g("Unit").world_position(unit, 0)
					local x, y, inside = api.world.to_screen({ x = V3.x(at), y = V3.y(at), z = V3.z(at) + CHEST })
					if x and inside then
						local cx, cy = x - M.LEFT * scale, y + M.UP * scale
						if p then
							kit:opacity(alpha)
							M.draw(kit, cx, cy, p, scale * grow)
						else
							kit:opacity(ammo_alpha)
							local fill, ccw, color, segments = ammo_circle.look(kind, share, rounds, empty, size, ready)
							M.draw(kit, cx, cy, fill, scale, { fill = color, ccw = ccw, size = segments,
								track = empty and ammo_circle.flash(clock) or nil })
							if empty and rounds then
								kit:layer(424)
								ammo_circle.draw_button(kit, ammo_circle.reload_button(player.pad), cx, cy, 2 * M.inner_radius(scale) * BUTTON)
							end
						end
						kit:opacity(1)
					end
				end
			end
		end)
		if not ok and not failed then
			failed = true
			obsidian.log("betterhud: reload and ammo circles: " .. tostring(err))
		end
	end)
end

return M
