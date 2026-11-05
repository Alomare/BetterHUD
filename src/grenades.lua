-- The grenades on each player's loadout card. The game draws two grenade icons, one per grenade it can
-- hold (Hud.draw_inventory, the loop over `grenade_01` at the end): slot 1 at the card's grenade_icon
-- position and slot 2 grenade_icon.y_offset design units higher (the HUD's space is y up), each white
-- while num_grenades reaches it and grey otherwise.
--
-- Grenade counter: the lower icon (slot 1) goes clear and an "x#" with the real num_grenades takes its
-- place, so counts above two show (Helldivers Arcade can raise the count; the network field holds 0-15).
-- The upper icon (slot 2) then stays white from one grenade up and grey at none, and the counter is grey
-- at none as well.
--
-- Charge meter: other mods call grenade_meter(unit, fraction) (exported from main.lua) to show a charge
-- on the upper icon of the card whose player avatar is `unit`: the game's icon at 30% opacity underneath,
-- and over it a full-opacity copy cut from the left to `fraction` of the width, by drawing the left part
-- of the texture (UV x from 0 to fraction) at that share of the width. This works with the counter off too.
--
-- The icons are retained images of the HUD's gui that the game only touches when the count or the card's
-- fade changes. Their ids are caught by watching the hd_gui's create_image and update_image while the
-- game's draw_inventory runs, matched by position, and kept with the key the game stores them under, so
-- an icon the game destroys (while a stratagem beacon is held) is noticed and let go.
local M = {}

local function g(name) return rawget(_G, name) end

M.DIM = 0.3 -- opacity of the icon under a charge meter
local GREY = 128 -- the game's grey for a slot without a grenade
local TEXT_SIZE = 0.8 -- of body_large's size
local CAP = 0.7 -- the height of the counter's digits, of the text size
local NEAR = 0.01 -- design units: how close a position must be to a slot's to count as that slot

local meters = {} -- avatar unit -> fraction from 0 to 1
local cards = setmetatable({}, { __mode = "k" }) -- the card's hud info table -> what is known of its icons

local function clamp(x) return math.max(0, math.min(1, x)) end

-- Drops the meters of units that are gone.
local function forget_gone()
	local alive = g("Unit") and g("Unit").alive
	if not alive then return end
	for unit in pairs(meters) do
		local ok, yes = pcall(alive, unit)
		if not (ok and yes) then meters[unit] = nil end
	end
end

-- grenade_meter(unit, fraction): fraction from 0 to 1 sets the meter for the player whose avatar is
-- `unit`, nil clears it. Answers true when the call was taken, false for a missing unit or a fraction
-- that isn't a number.
function M.meter(unit, fraction)
	if unit == nil then return false end
	if fraction == nil then
		meters[unit] = nil
		return true
	end
	fraction = tonumber(fraction)
	if not fraction or fraction ~= fraction then return false end
	meters[unit] = clamp(fraction)
	forget_gone()
	return true
end

-- The meter of a unit, for the tests.
function M.meter_of(unit) return meters[unit] end

-- How each slot looks: { opacity as a share of the card's fade, r, g, b }. Slot 1 is the lower icon.
-- counter: the grenade counter is on. metering: a charge meter is set for this card.
function M.looks(count, counter, metering)
	local function plain(lit) if lit then return { 1, 255, 255, 255 } end return { 1, GREY, GREY, GREY } end
	local s1, s2
	if counter then
		s1, s2 = { 0, 255, 255, 255 }, plain(count >= 1)
	else
		s1, s2 = plain(count >= 1), plain(count >= 2)
	end
	if metering then s2 = { M.DIM, 255, 255, 255 } end
	return s1, s2
end

-- The counter's words and color for a count.
function M.counter(count)
	count = math.max(0, math.floor(tonumber(count) or 0))
	if count >= 1 then return "x" .. count, { 255, 255, 255 } end
	return "x0", { GREY, GREY, GREY }
end

local function key_of(look, fade)
	return string.format("%.3f|%d|%d|%d", look[1] * fade, look[2], look[3], look[4])
end

local function card_of(info)
	local c = cards[info]
	if not c then
		c = { ids = {}, keys = {}, applied = {} }
		cards[info] = c
	end
	return c
end

-- Where the slots are, in the card's design units. The settings hold boxed vectors, plain tables with
-- x, y and z fields (Vector3Aux.box, Vector2Aux.box), read as they are: the game has no Vector2.x.
local function spot_of(info)
	local icon = info.equipment_info and info.equipment_info.grenade_icon
	local at, size = icon and icon.position, icon and icon.size
	if not (type(at) == "table" and type(size) == "table") then return nil end
	local x, y, w, h = tonumber(at.x), tonumber(at.y), tonumber(size.x), tonumber(size.y)
	if not (x and y and w and h) then return nil end
	return { x = x, y = y, z = tonumber(at.z) or 0, w = w, h = h, step = tonumber(icon.y_offset) or 0 }
end

local function slot_at(spot, pos)
	local V3 = g("Vector3")
	if math.abs(V3.x(pos) - spot.x) > NEAR then return nil end
	local y = V3.y(pos)
	if math.abs(y - spot.y) <= NEAR then return 1 end
	if math.abs(y - (spot.y + spot.step)) <= NEAR then return 2 end
	return nil
end

local function drop_fill(c, gui)
	if c.fill ~= nil and c.fill_gui == gui then pcall(gui.destroy_image, gui, c.fill) end
	c.fill, c.fill_gui = nil, nil
end

-- Runs the game's draw_inventory while catching the grenade icons' ids.
local function watched(original, gui, c, spot, ...)
	local own_create, own_update = rawget(gui, "create_image"), rawget(gui, "update_image")
	local create, update = gui.create_image, gui.update_image
	local touched = {}
	rawset(gui, "create_image", function(s, material, pos, ...)
		local id = create(s, material, pos, ...)
		local ok, slot = pcall(slot_at, spot, pos)
		if ok and slot then
			c.ids[slot], c.keys[slot], c.mat, touched[slot] = id, nil, material, true
		end
		return id
	end)
	rawset(gui, "update_image", function(s, id, material, pos, ...)
		update(s, id, material, pos, ...)
		local ok, slot = pcall(slot_at, spot, pos)
		if ok and slot then
			if c.ids[slot] ~= id then c.keys[slot] = nil end
			c.ids[slot], c.mat, touched[slot] = id, material, true
		end
	end)
	local ok, err = pcall(original, ...)
	rawset(gui, "create_image", own_create)
	rawset(gui, "update_image", own_update)
	if not ok then error(err, 0) end
	return touched
end

-- Whether the icon of a slot is still in the card's images, under the key the game keeps it.
local function still_there(c, slot, images)
	local id = c.ids[slot]
	if id == nil or type(images) ~= "table" then return false end
	local key = c.keys[slot]
	if key ~= nil and images[key] == id then return true end
	for k, v in pairs(images) do
		if v == id then
			c.keys[slot] = k
			return true
		end
	end
	return false
end

local function draw(gui, c, spot, touched, info, inventory, unit, counter_on)
	local V3, V2, Color = g("Vector3"), g("Vector2"), g("Color")
	local images = info.gui_objects and info.gui_objects.images
	for slot = 1, 2 do
		if not still_there(c, slot, images) then
			c.ids[slot], c.keys[slot], c.applied[slot] = nil, nil, nil
		end
	end
	if c.ids[1] == nil or c.ids[2] == nil or c.mat == nil then
		drop_fill(c, gui)
		return
	end
	local count = tonumber(inventory and inventory.num_grenades) or 0
	local fade = clamp(tonumber(info.fade) or 0)
	local fraction = unit ~= nil and meters[unit] or nil
	local want = { M.looks(count, counter_on, fraction ~= nil) }
	local game = { M.looks(count, false, false) }
	local size = V2(spot.w, spot.h)
	for slot = 1, 2 do
		if touched[slot] then c.applied[slot] = key_of(game[slot], fade) end
		local look = want[slot]
		local key = key_of(look, fade)
		if c.applied[slot] ~= key then
			local pos = V3(spot.x, spot.y + (slot - 1) * spot.step, spot.z)
			gui:update_image(c.ids[slot], c.mat, pos, size, Color(255 * look[1] * fade, look[2], look[3], look[4]))
			c.applied[slot] = key
		end
	end

	if fraction ~= nil then
		local pos = V3(spot.x, spot.y + spot.step, spot.z + 1)
		local cut = V2(spot.w * fraction, spot.h)
		local color = Color(fraction > 0 and 255 * fade or 0, 255, 255, 255)
		local uv0, uv1 = V2(0, 0), V2(fraction, 1)
		if c.fill ~= nil and c.fill_gui ~= gui then c.fill, c.fill_gui = nil, nil end
		if c.fill ~= nil then
			gui:update_image(c.fill, c.mat, pos, cut, color, uv0, uv1)
		else
			c.fill, c.fill_gui = gui:create_image(c.mat, pos, cut, color, uv0, uv1), gui
		end
	else
		drop_fill(c, gui)
	end

	if counter_on then
		local text, rgb = M.counter(count)
		gui:set_current_font("body_large")
		local text_size = g("FontSettings").fonts.body_large.font_size * TEXT_SIZE
		local width = gui:get_text_extents(text, nil, text_size) / gui.ui_scale
		local at = V3(spot.x + (spot.w - width) / 2, spot.y + (spot.h - text_size * CAP) / 2, spot.z + 1)
		gui:text(text, at, Color(255 * fade, rgb[1], rgb[2], rgb[3]), nil, text_size)
	end
end

function M.install(counter_on)
	obsidian.hook("Hud", "draw_inventory", function(original, self, a1, a2, dt, unit, info, inventory, ...)
		local gui = self and self.hd_gui
		local ready, spot = false, nil
		if type(gui) == "table" and type(info) == "table" then ready, spot = pcall(spot_of, info) end
		if not (ready and spot) then
			if type(info) == "table" and not M.told then
				M.told = true
				obsidian.log("betterhud: grenades: no grenade icon spot on a card: " .. tostring(spot))
			end
			return original(self, a1, a2, dt, unit, info, inventory, ...)
		end
		local c = card_of(info)
		-- Icons made before Better HUD watched (or lost track of): a count the game hasn't drawn makes it
		-- touch both again.
		if c.ids[1] == nil or c.ids[2] == nil then info.previous_num_grenades = -1 end
		local touched = watched(original, gui, c, spot, self, a1, a2, dt, unit, info, inventory, ...)
		forget_gone()
		local ok, err = pcall(draw, gui, c, spot, touched, info, inventory, unit, counter_on() == true)
		if not ok then obsidian.log("betterhud: grenades: " .. tostring(err)) end
	end)
end

return M
