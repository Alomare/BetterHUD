-- Better HUD: more on the game's HUD, each part a setting on the pause menu's Mods page.
local ammo = obsidian.module("src/ammo")
local health = obsidian.module("src/health")
local enemies = obsidian.module("src/enemies")
local world_bars = obsidian.module("src/world_bars")
local numbers = obsidian.module("src/numbers")
local reload = obsidian.module("src/reload")

local api = obsidian.import("obsidian.api")

-- The defaults. An Obsidian API without Mod Settings (before 1.11) keeps them.
local on = {
	ammo = true, player_health = true, player_health_numbers = false, enemy_health = true,
	hide_world_health = false, hide_world_get_up = false,
	damage_numbers = "both", damage_numbers_mode = "accumulated", damage_numbers_position = "entity",
	reload_circle = true,
}

local function choices(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = { id = c[1], label = c[2] } end
	return out
end

if api.mod_settings then
	local page = api.mod_settings.page("Better HUD")
	local function toggle(id, label, info)
		on[id] = page:toggle(id, { label = label, info = info, default = on[id], on_change = function(v) on[id] = v end })
	end
	local function choice(id, label, list, info)
		on[id] = page:choice(id, { label = label, info = info, default = on[id], choices = choices(list), on_change = function(v) on[id] = v end })
	end
	toggle("ammo", "Ammo counter", "Rounds left in the magazine, over the magazine count, for weapons that fire rounds. Hidden while calling a stratagem.")
	toggle("player_health", "Player health bars", "A health bar under each player card, with a white chunk fading where health was lost and a cyan shield bar over it while a shield holds.")
	toggle("player_health_numbers", "Health numbers", "Current and maximum health on each player health bar.")
	toggle("enemy_health", "Enemy health bars", "A bar over every enemy the player hits and every heavy that any player hurts.")
	toggle("reload_circle", "Reload circle", "A ring to the right of each local Helldiver that fills while the weapon in hand reloads.")
	toggle("hide_world_health", "Hide on-player health bar", "Hides the health bar the game draws over each Helldiver.")
	toggle("hide_world_get_up", "Hide on-player recovery bar", "Hides the bar the game draws over a downed Helldiver getting back up.")
	choice("damage_numbers", "Damage numbers", { { "off", "Off" }, { "enemies", "Enemies" }, { "players", "Players" }, { "both", "Both" } },
		"Numbers that rise and fade where damage lands: on enemies the player hits, on players losing health, or both.")
	-- Before 1.7.0 the mode had an Off too. A kept Off moves to "Damage numbers", so numbers that were
	-- off stay off, and the mode goes back to the default. The row is made with Off first, to read it,
	-- then again without, which takes its place.
	local MODES = { { "stacked", "Stacked" }, { "accumulated", "Accumulated" } }
	local MODE_INFO = "Stacked shows a number for each hit. Accumulated adds up hits on one target less than 0.3 seconds apart into one number."
	if page:choice("damage_numbers_mode", { default = on.damage_numbers_mode, choices = choices({ { "off", "Off" }, MODES[1], MODES[2] }) }) == "off" then
		page:set("damage_numbers_mode", on.damage_numbers_mode)
		page:set("damage_numbers", "off")
	end
	choice("damage_numbers_mode", "Damage numbers mode", MODES, MODE_INFO)
	choice("damage_numbers_position", "Damage numbers position",
		{ { "entity", "Next to the entity" }, { "bar", "Above health bar" }, { "hit", "At damage instance" } },
		"Above health bar needs Enemy health bars, and uses the entity spot where no bar shows. At damage instance uses the spot each hit landed.")
end

ammo.install(function() return on.ammo end)
health.install(function() return on.player_health end, function() return on.player_health_numbers end)
enemies.install(function() return on.enemy_health end)
world_bars.install(function() return on.hide_world_health end, function() return on.hide_world_get_up end)
reload.install(function() return on.reload_circle end)
numbers.install(function() return on.damage_numbers end, function() return on.damage_numbers_mode end,
	function() return on.damage_numbers_position end)

obsidian.log("Better HUD " .. tostring(obsidian.version) .. " ready")
