-- Better HUD: more on the game's HUD, each part a setting on the pause menu's Mod Settings page.
local ammo = obsidian.module("src/ammo")
local health = obsidian.module("src/health")
local enemies = obsidian.module("src/enemies")
local world_bars = obsidian.module("src/world_bars")

local api = obsidian.import("obsidian.api")

-- Every part is on until the player turns it off. An Obsidian API without Mod Settings (before 1.11)
-- leaves them all on.
local on = { ammo = true, player_health = true, enemy_health = true, enemy_which = "damaged", hide_world_health = true, hide_world_get_up = true }

if api.mod_settings then
	local page = api.mod_settings.page("Better HUD")
	local function toggle(id, label, info)
		on[id] = page:toggle(id, { label = label, info = info, default = true, on_change = function(v) on[id] = v end })
	end
	toggle("ammo", "Ammo counter", "Rounds left, a laser's heat or an arc weapon's charge, beside the magazine picture.")
	toggle("player_health", "Player health bars", "A health bar under each player's card.")
	toggle("enemy_health", "Enemy health bars", "A health bar over enemies that have lost health.")
	on.enemy_which = page:choice("enemy_which", { label = "Enemy bars on", default = "damaged",
		choices = { { id = "damaged", label = "Every damaged enemy" }, { id = "heavies", label = "Damaged heavies" } },
		info = "Which enemies get a health bar once hurt.", on_change = function(v) on.enemy_which = v end })
	toggle("hide_world_health", "Hide on-character health bar", "The game's own health bar over each Helldiver.")
	toggle("hide_world_get_up", "Hide on-character recovery bar", "The game's own bar over a downed Helldiver getting back up.")
end

ammo.install(function() return on.ammo end)
health.install(function() return on.player_health end)
enemies.install(function() return on.enemy_health end, function() return on.enemy_which == "heavies" end)
world_bars.install(function() return on.hide_world_health end, function() return on.hide_world_get_up end)

obsidian.log("Better HUD " .. tostring(obsidian.version) .. " ready")
