-- The rounds left in the magazine, as a number over the count of magazines, in the game's own HUD, for
-- the weapons that fire counted rounds: guns, flamethrowers and launchers. Lasers and arc weapons heat
-- or charge up instead, and get nothing. The magazine picture only knows the weapon's own size, so a
-- bigger magazine (Super Earth Survivors' Extended Mag) shows here too.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local RISE = 21 -- design pixels above the count of magazines
local SIZE = 0.9 -- of the count's own size
local WHITE = { 255, 255, 255, 255 }

-- The components of the weapons that fire counted rounds. A beamweapon (laser) or arcweapon has none.
local MAGAZINE_KINDS = { "firearm", "flameweapon", "launcher" }

-- The words and their colour for a weapon's state, or nil for nothing.
function M.reading(state)
	if not (state.rounds and state.magazine_capacity and state.magazine_capacity > 0) then return nil end
	return tostring(math.max(math.floor(state.rounds), 0)), WHITE
end

local function weapon_state(weapon)
	for _, kind in ipairs(MAGAZINE_KINDS) do
		local ctx = api.game.slaves(kind)[weapon] or api.game.masters(kind)[weapon]
		if ctx and ctx.state then return ctx.state end
	end
	return nil
end

-- Whether the player is calling a stratagem: entering a code (the card's "stratagems" state, from
-- CharacterComponent.get_hud_state) or holding the beacon to throw, where the game swaps the magazine
-- picture for the stratagem's (Hud.draw_inventory: held_grenade with a stratagem component).
function M.on_stratagem(info, inventory, has_component)
	if info and info.state == "stratagems" then return true end
	local held = inventory and inventory.held_grenade
	return held ~= nil and not inventory.grenade_thrown and has_component(held, "stratagem") == true
end

local function draw(hud, info, inventory)
	if M.on_stratagem(info, inventory, g("EntityAux").has_component) then return end
	local weapon = inventory and inventory.current_weapon
	-- No magazine picture, as for the REP-80: nothing to put a number over.
	local icon = info and info.equipment_info and info.equipment_info.ammo_icon
	if not (weapon and icon and icon.position and icon.text_offset) then return end
	local state = weapon_state(weapon)
	if not state then return end
	local text, colour = M.reading(state)
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
