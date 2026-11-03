-- Better HUD: more on the game's HUD, each part a setting on the pause menu's Mod Settings page.
local ammo = obsidian.module("src/ammo")
local health = obsidian.module("src/health")
local enemies = obsidian.module("src/enemies")

local api = obsidian.import("obsidian.api")

-- Every part is on until the player turns it off. An Obsidian API without Mod Settings (before 1.11)
-- leaves them all on.
local on = { ammo = true, player_health = true, enemy_health = true, enemy_which = "damaged" }

if api.mod_settings then
	local page = api.mod_settings.page("Better HUD")
	local function toggle(id, label, info)
		on[id] = page:toggle(id, { label = label, info = info, default = true, on_change = function(v) on[id] = v end })
	end
	toggle("ammo", "Ammo counter", "Rounds left beside the magazine picture.")
	toggle("player_health", "Player health bars", "A health bar under each player's card.")
	toggle("enemy_health", "Enemy health bars", "A health bar over enemies that have lost health.")
	on.enemy_which = page:choice("enemy_which", { label = "Enemy bars on", default = "damaged",
		choices = { { id = "damaged", label = "Every damaged enemy" }, { id = "heavies", label = "Damaged heavies" } },
		info = "Which enemies get a health bar once hurt.", on_change = function(v) on.enemy_which = v end })
end

ammo.install(function() return on.ammo end)
health.install(function() return on.player_health end)
enemies.install(function() return on.enemy_health end, function() return on.enemy_which == "heavies" end)

obsidian.log("Better HUD " .. tostring(obsidian.version) .. " ready")
