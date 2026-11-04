-- The settings: obsidian.json's options against the Mods page's rows, and the move of values kept in
-- game before 1.8.0 into the options (src/settings.lua).
local settings = obsidian.module("src/settings")

-- Enough JSON for obsidian.json.
local function decode(s)
	local i = 1
	local value
	local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
	local function str()
		local out = {}
		i = i + 1
		while true do
			local c = s:sub(i, i)
			if c == '"' then i = i + 1 break end
			if c == "\\" then
				local e = s:sub(i + 1, i + 1)
				out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e
				i = i + 2
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
		return table.concat(out)
	end
	function value()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local t = {}
			i = i + 1
			ws()
			if s:sub(i, i) == "}" then i = i + 1 return t end
			while true do
				ws()
				local k = str()
				ws()
				i = i + 1 -- :
				t[k] = value()
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then return t end
			end
		elseif c == "[" then
			local t = {}
			i = i + 1
			ws()
			if s:sub(i, i) == "]" then i = i + 1 return t end
			while true do
				t[#t + 1] = value()
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then return t end
			end
		elseif c == '"' then
			return str()
		elseif s:sub(i, i + 3) == "true" then
			i = i + 4
			return true
		elseif s:sub(i, i + 4) == "false" then
			i = i + 5
			return false
		elseif s:sub(i, i + 3) == "null" then
			i = i + 4
			return nil
		end
		local num = s:match("^-?[%d%.eE+-]+", i)
		i = i + #num
		return tonumber(num)
	end
	return value()
end

local function manifest()
	local f = assert(io.open("obsidian.json", "rb"))
	local text = f:read("*a")
	f:close()
	return decode(text)
end

-- A stand-in for Obsidian API's mod_settings (lib/mod_settings.lua): rows keep values under
-- "mod_settings/<mod>/<id>", or "option/<mod>/<id>" for a row bound to an option, which then starts from
-- the option's value in Obsidian.
local MOD = "alomare.betterhud"

local function fake_api(saved, binds, profile)
	local page = { rows = {} }
	local function key(row) return (row.option and "option/" or "mod_settings/") .. MOD .. "/" .. row.id end
	local function fits(row, v)
		if row.kind == "toggle" then return type(v) == "boolean" end
		for _, c in ipairs(row.choices) do
			if c.id == v then return true end
		end
		return false
	end
	local function add(kind, id, opts)
		local row = { kind = kind, id = id, option = opts.option == true, on_change = opts.on_change, label = opts.label, info = opts.info }
		if kind == "toggle" then
			row.default = opts.default == true
		else
			row.choices = opts.choices
			row.default = fits(row, opts.default) and opts.default or opts.choices[1].id
		end
		local placed = false
		for i, r in ipairs(page.rows) do
			if r.id == id then
				page.rows[i] = row
				placed = true
			end
		end
		if not placed then page.rows[#page.rows + 1] = row end
		local v = saved[key(row)]
		if v == nil and row.option then v = profile[id] end
		if v ~= nil and fits(row, v) then row.value = v else row.value = row.default end
		return row.value
	end
	function page:toggle(id, opts) return add("toggle", id, opts) end
	function page:choice(id, opts) return add("choice", id, opts) end
	function page:set(id, v)
		for _, row in ipairs(self.rows) do
			if row.id == id then
				if not fits(row, v) then return false end
				if row.value ~= v then
					row.value = v
					saved[key(row)] = v
					if row.on_change then row.on_change(v) end
				end
				return true
			end
		end
		return false
	end
	return { BINDS = binds or nil, page = function() return page end }, page
end

-- Obsidian's values: the profile's, else the manifest's default.
local function getter(profile)
	local defaults = {}
	for _, o in ipairs(manifest().options) do defaults[o.id] = o.default end
	return function(id)
		if profile[id] ~= nil then return profile[id] end
		return defaults[id]
	end
end

local function store(t)
	return { get = function(k, d) if t[k] == nil then return d end return t[k] end, set = function(k, v) t[k] = v end }
end

-- What Obsidian does while the game is closed: takes the pending values into the profile.
local function take(saved, profile)
	for k, v in pairs(saved) do
		local id = k:match("^option/" .. MOD:gsub("%.", "%%.") .. "/(.+)$")
		if id then
			profile[id] = v
			saved[k] = nil
		end
	end
end

return {
	{ "obsidian.json lists every row, with the same ids, defaults, choices and words", function()
		local options = manifest().options
		eq(#options, #settings.ROWS, "options")
		for i, row in ipairs(settings.ROWS) do
			local o = options[i]
			eq(o.id, row.id, "id " .. i)
			-- Obsidian's rule for an option id (core/src/options.rs is_key_name).
			eq(#row.id <= 32 and row.id:match("^[a-z0-9_]+$") ~= nil, true, row.id .. " is a valid option id")
			eq(o.type, row.kind, row.id .. " type")
			eq(o.default, row.default, row.id .. " default")
			eq(o.label.en, row.label, row.id .. " label")
			eq(o.description.en, row.info, row.id .. " description")
			eq(o.choices == nil, row.choices == nil, row.id .. " choices")
			for k, c in ipairs(row.choices or {}) do
				eq(o.choices[k].id, c.id, row.id .. " choice " .. k)
				eq(o.choices[k].label.en, c.label, row.id .. " choice label " .. k)
			end
			if row.choices then eq(#o.choices, #row.choices, row.id .. " choice count") end
			eq(settings.fits(row, row.default), true, row.id .. " default fits")
			-- The game's languages say what src/words.lua says, and Obsidian's zh-CN has every text too.
			local label, info, choices = settings.translated(row)
			for _, lang in ipairs(settings.LANGUAGES) do
				eq(o.label[lang], label[lang], row.id .. " label " .. lang)
				eq(o.description[lang], info[lang], row.id .. " description " .. lang)
				for k, c in ipairs(choices or {}) do eq(o.choices[k].label[lang], c.label[lang], row.id .. " choice " .. k .. " " .. lang) end
			end
			eq(type(o.label["zh-CN"]) == "string" and type(o.description["zh-CN"]) == "string", true, row.id .. " zh-CN")
			for k in ipairs(row.choices or {}) do eq(type(o.choices[k].label["zh-CN"]), "string", row.id .. " choice " .. k .. " zh-CN") end
		end
		local m = manifest()
		for _, lang in ipairs({ "fr", "es", "pt-BR", "zh-CN" }) do eq(type(m.description[lang]), "string", "description " .. lang) end
	end },

	{ "every translation is there, in Latin-1 for the game's font, without repeating the name", function()
		for _, row in ipairs(settings.ROWS) do
			local label, info, choices = settings.translated(row)
			for _, lang in ipairs(settings.LANGUAGES) do
				local texts = { label[lang], info[lang] }
				for _, c in ipairs(choices or {}) do texts[#texts + 1] = c.label[lang] end
				for _, t in ipairs(texts) do
					eq(type(t), "string", row.id .. " " .. lang)
					-- Two-byte UTF-8 from \194\128 to \195\191 is Latin-1; anything longer isn't.
					eq(t:find("[\196-\244]"), nil, row.id .. " " .. lang .. " outside Latin-1: " .. t)
				end
				eq(info[lang]:lower():find(label[lang]:lower(), 1, true), nil, row.id .. " " .. lang .. " repeats the name")
			end
		end
	end },

	{ "the words follow the rules for public text", function()
		local m = manifest()
		local texts = { m.description.en }
		for _, row in ipairs(settings.ROWS) do
			texts[#texts + 1] = row.label
			texts[#texts + 1] = row.info
			-- A description doesn't repeat the option's name.
			eq(row.info:lower():find(row.label:lower(), 1, true), nil, row.id .. " repeats the name")
		end
		for _, t in ipairs(texts) do
			eq(t:find("%f[%a][Ii]ts%f[%A]"), nil, "\"its\" in: " .. t)
			for _, word in ipairs({ "I", "my", "me", "we", "our", "us", "you", "your" }) do
				eq(t:lower():find("%f[%a]" .. word:lower() .. "%f[%A]"), nil, "\"" .. word .. "\" in: " .. t)
			end
		end
	end },

	{ "the rows are bound to the options, with the same choices", function()
		local saved, profile = {}, {}
		local api, page = fake_api(saved, true, profile)
		settings.setup(api, getter(profile), store({}))
		eq(#page.rows, #settings.ROWS, "rows")
		for i, row in ipairs(settings.ROWS) do
			local r = page.rows[i]
			eq(r.id, row.id, "order")
			eq(r.option, true, row.id .. " bound")
			eq(r.default, row.default, row.id .. " default")
			-- An API with bound rows shows words by language.
			eq(r.label.en, row.label, row.id .. " label")
			eq(r.info.en, row.info, row.id .. " info")
			eq(r.label.fr, settings.translated(row).fr, row.id .. " label fr")
			if row.choices then
				eq(#r.choices, #row.choices, row.id .. " choices")
				for k, c in ipairs(row.choices) do eq(r.choices[k].id, c.id, row.id .. " choice " .. k) end
			end
		end
	end },

	{ "the rows start from Obsidian's values, and a change in game reaches them", function()
		local saved, profile = {}, { enemy_health = false, damage_numbers_position = "hit" }
		local api, page = fake_api(saved, true, profile)
		local on = settings.setup(api, getter(profile), store({}))
		eq(on.enemy_health, false, "from Obsidian")
		eq(on.damage_numbers_position, "hit", "from Obsidian")
		eq(on.ammo, true, "default")
		page:set("ammo_circle", false)
		eq(on.ammo_circle, false, "changed in game")
		eq(saved["option/" .. MOD .. "/ammo_circle"], false, "kept for Obsidian")
	end },

	{ "values kept in game before 1.8.0 move into the options once", function()
		-- Before 1.7.0: the mode's Off. And an ammo counter turned off.
		local saved = { ["mod_settings/" .. MOD .. "/damage_numbers_mode"] = "off", ["mod_settings/" .. MOD .. "/ammo"] = false,
			["mod_settings/" .. MOD .. "/reload_circle"] = true }
		local profile, kept = {}, {}
		local api = fake_api(saved, true, profile)
		local on = settings.setup(api, getter(profile), store(kept))
		eq(on.damage_numbers, "off", "numbers that were off stay off")
		eq(on.damage_numbers_mode, "accumulated", "the mode back to the default")
		eq(on.ammo, false, "the ammo counter stays off")
		eq(on.reload_circle, true, "a default stays")
		eq(saved["option/" .. MOD .. "/damage_numbers"], "off", "pending for Obsidian")
		eq(saved["option/" .. MOD .. "/ammo"], false, "pending for Obsidian")
		eq(saved["option/" .. MOD .. "/reload_circle"], nil, "nothing pending for a default")
		eq(kept[settings.MOVED], true, "done once")
		-- Obsidian takes them, then the player turns the ammo counter back on there.
		take(saved, profile)
		profile.ammo = true
		api = fake_api(saved, true, profile)
		on = settings.setup(api, getter(profile), store(kept))
		eq(on.ammo, true, "Obsidian's value wins over the old one")
		eq(on.damage_numbers, "off", "still off")
	end },

	{ "1.7's move of the mode's Off: damage numbers off, kept in game", function()
		local saved = { ["mod_settings/" .. MOD .. "/damage_numbers"] = "off", ["mod_settings/" .. MOD .. "/damage_numbers_mode"] = "accumulated" }
		local profile = {}
		local on = settings.setup(fake_api(saved, true, profile), getter(profile), store({}))
		eq(on.damage_numbers, "off", "off")
		eq(on.damage_numbers_mode, "accumulated", "mode")
	end },

	{ "an API without bound rows keeps the rows apart, and still moves the mode's Off", function()
		local saved = { ["mod_settings/" .. MOD .. "/damage_numbers_mode"] = "off" }
		local profile = { enemy_health = false }
		local api, page = fake_api(saved, false, profile)
		local on = settings.setup(api, getter(profile), store({}))
		eq(on.damage_numbers, "off", "numbers off")
		eq(on.damage_numbers_mode, "accumulated", "mode back to the default")
		eq(on.enemy_health, false, "Obsidian's value as the default")
		for _, r in ipairs(page.rows) do eq(r.option, false, r.id .. " unbound") end
		eq(saved["option/" .. MOD .. "/damage_numbers"], nil, "nothing for Obsidian")
	end },

	{ "no Mods page: Obsidian's values", function()
		local profile = { reload_circle = false, damage_numbers = "players" }
		local on = settings.setup(nil, getter(profile), nil)
		eq(on.reload_circle, false, "toggle")
		eq(on.damage_numbers, "players", "choice")
		eq(on.ammo_circle, true, "default")
		on = settings.setup(nil, nil, nil)
		eq(on.reload_circle, true, "no settings at all: the defaults")
	end },
}
