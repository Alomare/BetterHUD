-- Better HUD's settings. Each one is an option in obsidian.json, set in Obsidian, and a row on the pause
-- menu's Mods page. From Obsidian API 1.16.0 on (api.mod_settings.BINDS) a row is bound to the option of
-- the same id, so a change in either place shows in the other. tests/run.lua checks that obsidian.json
-- lists the same ids, defaults, choices and words as ROWS.
local M = {}

M.TITLE = "Better HUD"

M.ROWS = {
	{ id = "ammo", kind = "toggle", default = true, label = "Ammo counter",
		info = "Rounds left in the magazine, over the magazine count, for weapons that fire rounds. Hidden while calling a stratagem." },
	{ id = "player_health", kind = "toggle", default = true, label = "Player health bars",
		info = "A red bar under each player card, with a white chunk fading where health was lost and a yellow bar over it while a shield holds." },
	{ id = "player_health_numbers", kind = "toggle", default = false, label = "Health numbers",
		info = "Current and maximum health at the left of each player bar." },
	{ id = "enemy_health", kind = "toggle", default = true, label = "Enemy health bars",
		info = "A bar over every enemy the player hits and every heavy that any player hurts." },
	{ id = "reload_circle", kind = "toggle", default = true, label = "Reload circle",
		info = "A ring to the right of each local Helldiver that fills while the weapon in hand reloads." },
	{ id = "ammo_circle", kind = "toggle", default = true, label = "Ammo circle",
		info = "A yellow ring beside each local Helldiver with the share of the magazine or charge left. Empty, the ring flashes red, with the reload button inside for weapons that fire rounds. Fades out 8 seconds after the last shot." },
	{ id = "hide_world_health", kind = "toggle", default = false, label = "Hide on-player health bar",
		info = "Takes away the game's own red bar over each Helldiver." },
	{ id = "hide_world_get_up", kind = "toggle", default = false, label = "Hide on-player recovery bar",
		info = "Takes away the game's own bar over a downed Helldiver getting back up." },
	{ id = "damage_numbers", kind = "choice", default = "both", label = "Damage numbers",
		info = "The damage dealt, where it lands: on enemies the player hits, on players losing health, or both.",
		choices = { { id = "off", label = "Off" }, { id = "enemies", label = "Enemies" }, { id = "players", label = "Players" }, { id = "both", label = "Both" } } },
	{ id = "damage_numbers_mode", kind = "choice", default = "accumulated", label = "Damage numbers mode",
		info = "Stacked shows a number for each hit, rising out of the way at once. Accumulated adds every hit on one target into one number that stays in place and fades out, and a new one starts only once it is gone.",
		choices = { { id = "stacked", label = "Stacked" }, { id = "accumulated", label = "Accumulated" } } },
	{ id = "damage_numbers_position", kind = "choice", default = "entity", label = "Damage numbers position",
		info = "Above health bar needs Enemy health bars, and uses the entity spot where no bar shows. At damage instance uses the spot each hit landed.",
		choices = { { id = "entity", label = "Next to the entity" }, { id = "bar", label = "Above health bar" }, { id = "hit", label = "At damage instance" } } },
}

-- Before 1.7.0 the damage numbers mode had an Off too.
local OLD_MODE_CHOICES = { { id = "off", label = "Off" }, { id = "stacked", label = "Stacked" }, { id = "accumulated", label = "Accumulated" } }

-- Set in Better HUD's storage once the in-game values kept before 1.8.0 have moved into the options.
M.MOVED = "settings_moved_to_options"

function M.row(id)
	for _, row in ipairs(M.ROWS) do
		if row.id == id then return row end
	end
	return nil
end

-- Whether a value fits a row: a boolean for a toggle, one of the choice ids for a choice.
function M.fits(row, v)
	if row.kind == "toggle" then return type(v) == "boolean" end
	for _, c in ipairs(row.choices) do
		if c.id == v then return true end
	end
	return false
end

local function make(page, row, opts)
	if row.kind == "toggle" then return page:toggle(row.id, opts) end
	return page:choice(row.id, opts)
end

-- The values to start with, and the Mods page's rows that keep them up to date.
-- mod_settings: api.mod_settings, or nil before Obsidian API 1.11. get: obsidian.settings.get, or nil.
-- storage: obsidian.storage, or nil. Answers a table of id → value that the rows change in place.
function M.setup(mod_settings, get, storage)
	local on = {}
	for _, row in ipairs(M.ROWS) do
		on[row.id] = row.default
		if get then
			local ok, v = pcall(get, row.id)
			if ok and M.fits(row, v) then on[row.id] = v end
		end
	end
	if not mod_settings then return on end
	local page = mod_settings.page(M.TITLE)
	local bind = mod_settings.BINDS == true

	local function opts_of(row, extra)
		local o = { label = row.label, info = row.info, choices = row.choices,
			on_change = function(v) on[row.id] = v end }
		for k, v in pairs(extra) do o[k] = v end
		return o
	end

	if not bind then
		-- An API before 1.16 keeps the rows apart from the options: the option's value is only the default.
		for _, row in ipairs(M.ROWS) do
			if row.id == "damage_numbers_mode" then
				-- A kept Off moves to "Damage numbers", so numbers that were off stay off, and the mode goes
				-- back to the default. The row is made with Off first, to read it, then again without.
				if page:choice(row.id, { default = on[row.id], choices = OLD_MODE_CHOICES }) == "off" then
					page:set(row.id, on[row.id])
					page:set("damage_numbers", "off")
				end
			end
			on[row.id] = make(page, row, opts_of(row, { default = on[row.id] }))
		end
		return on
	end

	-- Up to 1.7.1 the rows were in-game settings of their own. Once, what they kept that isn't the default
	-- goes into the options: each row is made unbound first, to read it, and the bound row replaces it.
	local kept = {}
	local move = storage ~= nil and not storage.get(M.MOVED, false)
	if move then
		for _, row in ipairs(M.ROWS) do
			local choices = row.id == "damage_numbers_mode" and OLD_MODE_CHOICES or row.choices
			local v = make(page, row, { default = row.default, choices = choices })
			if v ~= row.default then kept[#kept + 1] = { row.id, v } end
		end
	end
	for _, row in ipairs(M.ROWS) do
		on[row.id] = make(page, row, opts_of(row, { option = true, default = row.default }))
	end
	if move then
		local mode_off = false
		for _, k in ipairs(kept) do
			if k[1] == "damage_numbers_mode" and k[2] == "off" then mode_off = true else page:set(k[1], k[2]) end
		end
		if mode_off then page:set("damage_numbers", "off") end
		storage.set(M.MOVED, true)
	end
	return on
end

return M
