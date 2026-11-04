-- The ammo circle: the reload circle's ring (src/reload.lua draws both, in the same spot), in yellow,
-- filled with the share of the magazine left, or for a laser or arc weapon the share of heat left before
-- it overheats. Empty, the dark track flashes between black and a dark red, and a weapon that fires
-- rounds shows the reload button in the middle. The ring shows from a shot on, and fades out FADE
-- seconds once SHOW seconds have passed without one.
local M = {}

local function g(name) return rawget(_G, name) end

M.SHOW, M.FADE = 8, 1 -- seconds after the last shot at full strength; seconds to fade out
M.FLASH = 0.8 -- seconds from black to dark red and back, while empty
-- The yellow of the game's shield bar (hud_settings.lua foreground_shield), and a lighter inner half.
M.FILL, M.LIT = { 255, 190, 17, 255 }, { 255, 225, 120, 255 }
M.BLACK, M.RED = { 0, 0, 0, 200 }, { 125, 12, 12, 215 }
local INK = { 255, 255, 255, 255 }

local function clamp(x) return math.max(0, math.min(1, x)) end

-- What a weapon's state shows: the share left (0 to 1), whether it counts rounds, and whether it's
-- empty. nil for a state with neither rounds nor heat. Firearms, flamethrowers and launchers keep
-- rounds and magazine_capacity; lasers and arc weapons keep heat from 0 to 1 (beamweapon_component.lua,
-- arcweapon_component.lua), and at 1 they overheat.
function M.reading(state)
	if type(state) ~= "table" then return nil end
	local rounds, size = state.rounds, state.magazine_capacity
	if type(rounds) == "number" and type(size) == "number" and size > 0 then
		local left = math.max(math.floor(rounds), 0)
		return clamp(left / size), true, left <= 0
	end
	if type(state.heat) == "number" then
		return clamp(1 - state.heat), false, state.heat >= 1 or state.overheated == true
	end
	return nil
end

-- Keeps `t` up to date for a frame: a share that went down on the same weapon is a shot.
function M.track(t, weapon, share, now)
	if weapon ~= nil and t.weapon == weapon and t.share and share < t.share - 1e-4 then t.shot = now end
	t.weapon, t.share = weapon, share
end

-- How visible the ring is at `now`, from the time of the last shot (nil for none yet).
function M.alpha(shot, now)
	if not shot then return 0 end
	local idle = now - shot
	if idle <= M.SHOW then return 1 end
	return math.max(0, 1 - (idle - M.SHOW) / M.FADE)
end

-- The track's color at time `now` while empty: black, to dark red, and back, every FLASH seconds.
function M.flash(now)
	local f = 0.5 - 0.5 * math.cos(2 * math.pi * now / M.FLASH)
	local out = {}
	for i = 1, 4 do out[i] = math.floor(M.BLACK[i] + (M.RED[i] - M.BLACK[i]) * f + 0.5) end
	return out
end

-- A keyboard prompt is a key cap, a character of the game's font, then the key's name between two "¬"
-- marks, which HdGui.text draws over the cap (hd_gui.lua). A pad's prompt is one character. Answers the
-- cap and the name, or nil and the whole text when it has no marks.
function M.split_key(value)
	if type(value) ~= "string" or value == "" then return nil, nil end
	local cap, key = value:match("^(.-)\194\172(.-)\194\172")
	if cap and cap ~= "" then return cap, key end
	return nil, (value:gsub("\194\172", ""))
end

-- The reload button for a pad (nil: the main player's), as the game's text keeps it: from the modifier
-- set the game fills prompts from, else from obsidian.ui.prompt, which drops the marks.
function M.reload_button(pad)
	local lm = g("LocalizationManager")
	if pad == nil then
		local settings = g("GameSettings")
		local ok, main = pcall(function() return settings.get_main_pad_number() end)
		if ok then pad = main end
	end
	local set = pad == g("KEYBOARD_MOUSE_PAD_NUMBER") and "keyboard_mouse" or ("pad" .. tostring(pad))
	local mods = type(lm) == "table" and lm.modifier_sets and lm.modifier_sets[set]
	for _, m in ipairs(mods or {}) do
		if m.modifier == "#mod_reload" and type(m.value) == "string" then return m.value end
	end
	local ui = obsidian.ui
	return ui and ui.prompt and ui.prompt("reload", pad) or nil
end

-- Draws a prompt centred on cx, cy, as big as fits `room` pixels across: a pad's button as it is, a
-- keyboard's key cap with the key's name over it, shrunk until it fits the cap.
function M.draw_button(kit, value, cx, cy, room)
	local cap, key = M.split_key(value)
	local face = cap or key
	if not face or face == "" then return end
	local opts = { font = "body_large", size = room, color = INK }
	local w = kit:measure(face, opts)
	if w > room and w > 0 then
		opts.size = opts.size * room / w
		w = room
	end
	local base = cy - opts.size * 0.36
	kit:text(face, cx - w / 2, base, opts)
	if cap and key and key ~= "" then
		local inner = { font = "body_large", size = opts.size * 0.72, color = INK }
		while inner.size > 4 and kit:measure(key, inner) > w * 0.75 do inner.size = inner.size * 0.9 end
		local z = kit:layer()
		kit:layer(z + 1)
		kit:text(key, cx - kit:measure(key, inner) / 2, base + (opts.size - inner.size) * 0.36, inner)
		kit:layer(z)
	end
end

return M
