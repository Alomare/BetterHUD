-- What's left in the weapon, as a number over the count of magazines, in the game's own HUD: the rounds
-- in the magazine for guns, flamethrowers and launchers, the heat for lasers, and the charge for arc
-- weapons while they charge. The magazine picture only knows the weapon's own size, so a bigger magazine
-- (Super Earth Survivors' Extended Mag) shows here too.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local RISE = 21 -- design pixels above the count of magazines
local SIZE = 0.9 -- of the count's own size
local WHITE = { 255, 255, 255, 255 }
local HOT = { 255, 255, 55, 25 } -- the HUD's red, for a laser about to overheat
local HOT_FROM = 0.85

-- Each kind of weapon by its component, and what it shows: its words and their colour, or nil for nothing.
local KINDS = {
	{ "firearm", "rounds" }, { "flameweapon", "rounds" }, { "launcher", "rounds" },
	{ "beamweapon", "heat" }, { "arcweapon", "charge" },
}

local function percent(x) return tostring(math.floor(math.max(math.min(x, 1), 0) * 100 + 0.5)) .. "%" end

function M.reading(kind, state)
	if kind == "rounds" then
		if not (state.rounds and state.magazine_capacity and state.magazine_capacity > 0) then return nil end
		return tostring(math.max(math.floor(state.rounds), 0)), WHITE
	elseif kind == "heat" then
		if type(state.heat) ~= "number" then return nil end
		return percent(state.heat), state.heat >= HOT_FROM and HOT or WHITE
	elseif kind == "charge" then
		if type(state.heat) ~= "number" or state.heat <= 0 then return nil end
		return percent(state.heat), WHITE
	end
	return nil
end

local function weapon_state(weapon)
	for _, k in ipairs(KINDS) do
		local ctx = api.game.slaves(k[1])[weapon] or api.game.masters(k[1])[weapon]
		if ctx and ctx.state then return k[2], ctx.state end
	end
	return nil
end

local function draw(hud, info, inventory)
	local weapon = inventory and inventory.current_weapon
	-- No magazine picture, as for the REP-80: nothing to put a number over.
	local icon = info and info.equipment_info and info.equipment_info.ammo_icon
	if not (weapon and icon and icon.position and icon.text_offset) then return end
	local kind, state = weapon_state(weapon)
	if not kind then return end
	local text, colour = M.reading(kind, state)
	if not text then return end
	local V3, aux = g("Vector3"), g("Vector3Aux")
	local at = aux.unbox(icon.position)
	local off = aux.unbox(icon.text_offset)
	local gui = hud.hd_gui
	gui:set_current_font("body_large")
	local size = g("FontSettings").fonts.body_large.font_size * SIZE
	-- The right edge on the count's, as the game places that.
	local width = gui:get_text_extents(text, nil, size)
	gui:text(text, V3(V3.x(at) + V3.x(off) - width / gui.ui_scale, V3.y(at) + V3.y(off) + RISE, V3.z(at) + V3.z(off) + 1), g("Color")(colour[1], colour[2], colour[3], colour[4]), nil, size)
end

function M.install(active)
	obsidian.hook("Hud", "draw_inventory", function(original, self, a1, a2, a3, a4, info, inventory, ...)
		original(self, a1, a2, a3, a4, info, inventory, ...)
		if active() then
			local ok, err = pcall(draw, self, info, inventory)
			if not ok then obsidian.log("betterhud: ammo counter: " .. tostring(err)) end
		end
	end)
end

return M
