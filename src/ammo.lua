-- The rounds left in the magazine, as a number over the count of magazines, in the game's own HUD. The
-- magazine picture only knows the weapon's own size, so a bigger magazine (Super Earth Survivors'
-- Extended Mag) shows here too. Weapons without a magazine show nothing yet.
local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

local RISE = 21 -- design pixels above the count of magazines
local SIZE = 0.9 -- of the count's own size

local function draw(hud, info, inventory)
	local weapon = inventory and inventory.current_weapon
	local ctx = weapon and (api.game.slaves("firearm")[weapon] or api.game.masters("firearm")[weapon])
	local state = ctx and ctx.state
	if not (state and state.rounds and state.magazine_capacity and state.magazine_capacity > 0) then return end
	local V3, aux = g("Vector3"), g("Vector3Aux")
	local at = aux.unbox(info.equipment_info.ammo_icon.position)
	local off = aux.unbox(info.equipment_info.ammo_icon.text_offset)
	local gui = hud.hd_gui
	gui:set_current_font("body_large")
	local text = tostring(math.max(math.floor(state.rounds), 0))
	local size = g("FontSettings").fonts.body_large.font_size * SIZE
	-- Its right edge on the count's, as the game places that.
	local width = gui:get_text_extents(text, nil, size)
	gui:text(text, V3(V3.x(at) + V3.x(off) - width / gui.ui_scale, V3.y(at) + V3.y(off) + RISE, V3.z(at) + V3.z(off) + 1), g("Color")(255, 255, 255, 255), nil, size)
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
