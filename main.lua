-- Better HUD: more on the game's HUD, each part an option in Obsidian and a row on the pause menu's
-- Mods page (src/settings.lua).
local ammo = obsidian.module("src/ammo")
local health = obsidian.module("src/health")
local enemies = obsidian.module("src/enemies")
local world_bars = obsidian.module("src/world_bars")
local numbers = obsidian.module("src/numbers")
local reload = obsidian.module("src/reload")
local settings = obsidian.module("src/settings")

local api = obsidian.import("obsidian.api")

local on = settings.setup(api.mod_settings, obsidian.settings and obsidian.settings.get, obsidian.storage)

ammo.install(function() return on.ammo end)
health.install(function() return on.player_health end, function() return on.player_health_numbers end)
enemies.install(function() return on.enemy_health end)
world_bars.install(function() return on.hide_world_health end, function() return on.hide_world_get_up end)
reload.install(function() return on.reload_circle end, function() return on.ammo_circle end)
numbers.install(function() return on.damage_numbers end, function() return on.damage_numbers_mode end,
	function() return on.damage_numbers_position end)

obsidian.log("Better HUD " .. tostring(obsidian.version) .. " ready")
