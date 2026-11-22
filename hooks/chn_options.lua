local ok_boss, BossNames = pcall(dofile, "/hooks/chn-mod/random_boss_names.lua")
if not ok_boss then BossNames = dofile("hooks/random_boss_names.lua") end
local ok_art, ArtNames = pcall(dofile, "/hooks/chn-mod/random_artifact_names.lua")
if not ok_art then ArtNames = dofile("hooks/random_artifact_names.lua") end

local M = {
	RAND_BOSS_DESC = [[Generate culturally-grouped Chinese names for random rare and epic bosses in Simplified Chinese mode.
Default is enabled. Only takes effect when the game language is Simplified Chinese.
When disabled, existing and newly generated random bosses immediately revert to their original names. Re-enabling restores their Chinese names (previously written combat log lines are not retroactively changed).#WHITE#]],
	RAND_ART_DESC = [[Generate thematic Chinese names for identified random artifacts in Simplified Chinese mode.
Default is enabled. Only takes effect when the game language is Simplified Chinese.
When disabled, all random artifacts immediately display their original names. Re-enabling immediately restores their Chinese names.#WHITE#]],
}

local function ensure_settings_table()
	if type(_G.config) ~= "table" then
		_G.config = {}
	end
	if type(_G.config.settings) ~= "table" then
		_G.config.settings = {}
	end
	if type(_G.config.settings.chn_mod) ~= "table" then
		_G.config.settings.chn_mod = {}
	end
	return _G.config.settings.chn_mod
end

function M.is_randboss_enabled()
	return BossNames.is_enabled()
end

function M.is_randart_enabled()
	return ArtNames.is_enabled()
end

local function mark_ui_dirty(g)
	g = type(g) == "table" and g or rawget(_G, "game")
	if type(g) ~= "table" then return end
	if type(g.player) == "table" then
		g.player.changed = true
	end
	if type(g.level) == "table" and type(g.level.map) == "table" then
		g.level.map.changed = true
	end
end

function M.set_randboss_enabled(enabled, g)
	local val = (enabled ~= false)
	local cm = ensure_settings_table()
	cm.randboss_names = val
	g = type(g) == "table" and g or rawget(_G, "game")
	if type(g) == "table" and type(g.saveSettings) == "function" then
		g:saveSettings("chn_mod.randboss_names", ("chn_mod.randboss_names = %s\n"):format(tostring(val)))
	end
	pcall(BossNames.sync_all, g)
	mark_ui_dirty(g)
	return val
end

function M.set_randart_enabled(enabled, g)
	local val = (enabled ~= false)
	local cm = ensure_settings_table()
	cm.randart_names = val
	g = type(g) == "table" and g or rawget(_G, "game")
	if type(g) == "table" and type(g.saveSettings) == "function" then
		g:saveSettings("chn_mod.randart_names", ("chn_mod.randart_names = %s\n"):format(tostring(val)))
	end
	mark_ui_dirty(g)
	return val
end

local function to_tstring(s)
	if type(s) == "string" and type(s.toTString) == "function" then
		return s:toTString()
	end
	return s
end

local function make_zone(dialog, text)
	local ok_tz, Textzone = pcall(require, "engine.ui.Textzone")
	local w = (type(dialog) == "table" and type(dialog.c_desc) == "table" and dialog.c_desc.w) or 400
	local h = (type(dialog) == "table" and type(dialog.c_desc) == "table" and dialog.c_desc.h) or 400
	local ts = to_tstring(text)
	if ok_tz and type(Textzone) == "table" and type(Textzone.new) == "function" then
		return Textzone.new{width=w, height=h, text=ts}
	end
	return {width=w, height=h, text=ts}
end

function M.build_options_list(dialog)
	local t_fn = type(_G._t) == "function" and _G._t or function(s) return s end
	local list = {}

	list[#list+1] = {
		zone = make_zone(dialog, t_fn(M.RAND_BOSS_DESC)),
		name = to_tstring(t_fn("#GOLD##{bold}#Chinese random boss names#WHITE##{normal}#")),
		status = function()
			return tostring(M.is_randboss_enabled() and t_fn("enabled") or t_fn("disabled"))
		end,
		fct = function(item)
			M.set_randboss_enabled(not M.is_randboss_enabled())
			if type(dialog) == "table" and type(dialog.c_list) == "table" and type(dialog.c_list.drawItem) == "function" then
				dialog.c_list:drawItem(item)
			end
		end,
	}

	list[#list+1] = {
		zone = make_zone(dialog, t_fn(M.RAND_ART_DESC)),
		name = to_tstring(t_fn("#GOLD##{bold}#Chinese random artifact names#WHITE##{normal}#")),
		status = function()
			return tostring(M.is_randart_enabled() and t_fn("enabled") or t_fn("disabled"))
		end,
		fct = function(item)
			M.set_randart_enabled(not M.is_randart_enabled())
			if type(dialog) == "table" and type(dialog.c_list) == "table" and type(dialog.c_list.drawItem) == "function" then
				dialog.c_list:drawItem(item)
			end
		end,
	}

	return list
end

local installed_classes = setmetatable({}, {__mode = "k"})

function M.install(cls)
	if not cls then
		local ok, c = pcall(require, "engine.class")
		if ok then cls = c end
	end
	if type(cls) ~= "table" or type(cls.bindHook) ~= "function" then
		return false
	end
	if installed_classes[cls] then
		return true
	end
	installed_classes[cls] = true

	cls:bindHook("GameOptions:tabs", function(self, data)
		if type(data) == "table" and type(data.tab) == "function" then
			local t_fn = type(_G._t) == "function" and _G._t or function(s) return s end
			data.tab(t_fn("Localization"), function(dialog)
				dialog.list = M.build_options_list(dialog)
			end)
		end
	end)

	cls:bindHook("Game:changeLevel", function(self, data)
		local g = (type(self) == "table" and (self.level or self.zone or self.party)) and self or rawget(_G, "game")
		pcall(BossNames.sync_all, g)
	end)

	return true
end

return M
