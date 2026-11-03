-- Better HUD: more on the game's HUD, each part a setting on the pause menu's Mod Settings page.
local ammo = obsidian.module("src/ammo")
local health = obsidian.module("src/health")

local api = obsidian.import("obsidian.api")

-- Every part is on until the player turns it off. An Obsidian API without Mod Settings (before 1.11)
-- leaves them all on.
local on = { ammo = true, player_health = true }

if api.mod_settings then
	local page = api.mod_settings.page("Better HUD")
	local function toggle(id, label, info)
		on[id] = page:toggle(id, { label = label, info = info, default = true, on_change = function(v) on[id] = v end })
	end
	toggle("ammo", "Ammo counter", "Rounds left beside the magazine picture.")
	toggle("player_health", "Player health bars", "A health bar under each player's card.")
end

ammo.install(function() return on.ammo end)
health.install(function() return on.player_health end)

obsidian.log("Better HUD " .. tostring(obsidian.version) .. " ready")
