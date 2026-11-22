-- Comprehensive test suite for hooks/chn_options.lua, GameOptions Localization tab,
-- independent config persistence, and bidirectional dynamic switching for random bosses & artifacts.
-- Run from addon root with LuaJIT or Lua 5.1.

local real_dofile = dofile
local cached_modules = {}
dofile = function(path)
	if path == "/data-chn-mod/chn_random_names.lua" then path = "data/chn_random_names.lua" end
	if path == "/hooks/chn-mod/random_artifact_names.lua" then path = "hooks/random_artifact_names.lua" end
	if path == "/data-chn-mod/chn_randboss_names.lua" then path = "data/chn_randboss_names.lua" end
	if path == "/hooks/chn-mod/random_boss_names.lua" then path = "hooks/random_boss_names.lua" end
	if path == "/hooks/chn-mod/chn_options.lua" then path = "hooks/chn_options.lua" end
	if path == "data/chn_randboss_names.lua"
		or path == "hooks/random_boss_names.lua"
		or path == "data/chn_random_names.lua"
		or path == "hooks/random_artifact_names.lua"
		or path == "hooks/chn_options.lua"
	then
		if not cached_modules[path] then
			cached_modules[path] = real_dofile(path)
		end
		return cached_modules[path]
	end
	return real_dofile(path)
end

-- Strict RNG / clock guard
local orig_math_random = math.random
local orig_math_randomseed = math.randomseed
local orig_os_time = os.time
local orig_os_clock = os.clock

local function forbid_random_and_time()
	math.random = function() error("naming/options used math.random", 2) end
	math.randomseed = function() error("naming/options used math.randomseed", 2) end
	os.time = function() error("naming/options used os.time", 2) end
	os.clock = function() error("naming/options used os.clock", 2) end
	_G.rng = setmetatable({}, {
		__index = function(_, k)
			error("naming/options used engine rng." .. tostring(k), 2)
		end,
		__newindex = function()
			error("naming/options mutated engine rng", 2)
		end,
	})
end

forbid_random_and_time()

local function check(cond, label)
	if not cond then error("FAIL: " .. tostring(label), 2) end
	print("ok   " .. tostring(label))
end

package.loaded["engine.DamageType"] = {
	FIRE = "FIRE", COLD = "COLD", LIGHTNING = "LIGHTNING",
	LIGHT = "LIGHT", DARKNESS = "DARKNESS", ARCANE = "ARCANE", PHYSICAL = "PHYSICAL",
}

-- Load real T-Engine4 thirdparty/config.lua
real_dofile("/workspace/t-engine4/game/thirdparty/config.lua")
check(type(config) == "table" and type(config.loadString) == "function", "loaded real T-Engine4 thirdparty/config.lua")

local BossNames = dofile("/hooks/chn-mod/random_boss_names.lua")
local ArtNames = dofile("/hooks/chn-mod/random_artifact_names.lua")
local ChnOptions = dofile("/hooks/chn-mod/chn_options.lua")

-- ============================================================================
-- 1. Default values test
-- ============================================================================
do
	config.settings = {}
	check(BossNames.is_enabled() == true, "randboss enabled by default when config.settings.chn_mod is nil")
	check(ArtNames.is_enabled() == true, "randart enabled by default when config.settings.chn_mod is nil")
	check(ChnOptions.is_randboss_enabled() == true, "ChnOptions.is_randboss_enabled default true")
	check(ChnOptions.is_randart_enabled() == true, "ChnOptions.is_randart_enabled default true")

	config.settings.chn_mod = "invalid_non_table"
	check(BossNames.is_enabled() == true, "randboss enabled when chn_mod is not a table")
	check(ArtNames.is_enabled() == true, "randart enabled when chn_mod is not a table")

	config.settings.chn_mod = { randboss_names = false }
	check(BossNames.is_enabled() == false, "randboss disabled when explicitly false")
	check(ArtNames.is_enabled() == true, "randart still enabled when only randboss_names is false")

	config.settings.chn_mod = { randart_names = false }
	check(BossNames.is_enabled() == true, "randboss still enabled when only randart_names is false")
	check(ArtNames.is_enabled() == false, "randart disabled when explicitly false")

	config.settings.chn_mod = { randboss_names = 1, randart_names = "yes" }
	check(BossNames.is_enabled() == true, "randboss enabled unless == false")
	check(ArtNames.is_enabled() == true, "randart enabled unless == false")
end

-- ============================================================================
-- 2. Persistence round-trip with real thirdparty/config.lua
-- ============================================================================
do
	local saved_files = {}
	local mock_game = {
		saveSettings = function(self, file_key, content)
			saved_files[file_key] = content
		end,
		player = { changed = false },
		level = { map = { changed = false } },
	}

	config.settings = { locale = "zh_hans" }
	ChnOptions.set_randboss_enabled(false, mock_game)
	check(saved_files["chn_mod.randboss_names"] == "chn_mod.randboss_names = false\n", "saved chn_mod.randboss_names = false")
	check(mock_game.player.changed == true and mock_game.level.map.changed == true, "UI and map marked dirty on randboss toggle")

	mock_game.player.changed = false
	mock_game.level.map.changed = false
	ChnOptions.set_randart_enabled(true, mock_game)
	check(saved_files["chn_mod.randart_names"] == "chn_mod.randart_names = true\n", "saved chn_mod.randart_names = true")
	check(mock_game.player.changed == true and mock_game.level.map.changed == true, "UI and map marked dirty on randart toggle")

	-- Forward load order
	config.settings = {}
	local ok1, err1 = config.loadString(saved_files["chn_mod.randboss_names"])
	local ok2, err2 = config.loadString(saved_files["chn_mod.randart_names"])
	check(ok1 and ok2, "config.loadString succeeded in forward order: " .. tostring(err1 or err2))
	check(config.settings.chn_mod.randboss_names == false, "forward reload preserved randboss_names = false")
	check(config.settings.chn_mod.randart_names == true, "forward reload preserved randart_names = true")

	-- Reverse load order
	config.settings = {}
	local ok3, err3 = config.loadString(saved_files["chn_mod.randart_names"])
	local ok4, err4 = config.loadString(saved_files["chn_mod.randboss_names"])
	check(ok3 and ok4, "config.loadString succeeded in reverse order: " .. tostring(err3 or err4))
	check(config.settings.chn_mod.randboss_names == false, "reverse reload preserved randboss_names = false")
	check(config.settings.chn_mod.randart_names == true, "reverse reload preserved randart_names = true")

	-- Flip both and test reverse reload again
	ChnOptions.set_randboss_enabled(true, mock_game)
	ChnOptions.set_randart_enabled(false, mock_game)
	config.settings = {}
	assert(config.loadString(saved_files["chn_mod.randart_names"]))
	assert(config.loadString(saved_files["chn_mod.randboss_names"]))
	check(config.settings.chn_mod.randboss_names == true and config.settings.chn_mod.randart_names == false, "flipped reload preserved both settings independently")
end

-- ============================================================================
-- 3. Real engine/I18N.lua + data/chn_supplement.lua localization test
-- ============================================================================
do
	-- Minimal class + fs + util stubs required by real engine/I18N.lua
	local hook_registry = {}
	local mock_class = {
		make = function(m) return m end,
		inherit = function(...) return function(m) return m end end,
		bindHook = function(self, name, fn)
			hook_registry[name] = hook_registry[name] or {}
			table.insert(hook_registry[name], fn)
		end,
		triggerHook = function(self, data)
			local list = hook_registry[data[1]]
			if list then
				for _, fn in ipairs(list) do
					fn(self, data)
				end
			end
		end,
		_hook_registry = hook_registry,
	}
	package.loaded["engine.class"] = mock_class
	_G.class = mock_class

	_G.fs = {
		exists = function(path)
			local f = io.open(path, "r")
			if f then f:close() return true end
			return false
		end,
	}
	_G.util = {
		loadfilemods = function(file, env)
			local f, err = loadfile(file)
			if f then setfenv(f, env) end
			return f, err
		end,
	}

	assert(loadfile("/workspace/t-engine4/game/engines/default/engine/I18N.lua"))("engine.I18N")
	local I18N = package.loaded["engine.I18N"]
	I18N:loadLocale("data/chn_supplement.lua")
	-- Also add standard engine enabled/disabled into zh_hans
	I18N:t("zh_hans", "enabled", "已启用", "_t")
	I18N:t("zh_hans", "disabled", "已禁用", "_t")

	I18N:setLocale("zh_hans")
	check(_t("Localization") == "汉化", "zh_hans translates 'Localization' -> '汉化'")
	check(_t("#GOLD##{bold}#Chinese random boss names#WHITE##{normal}#") == "#GOLD##{bold}#随机怪物中文命名#WHITE##{normal}#", "zh_hans translates randboss option title")
	check(_t("#GOLD##{bold}#Chinese random artifact names#WHITE##{normal}#") == "#GOLD##{bold}#随机神器中文命名#WHITE##{normal}#", "zh_hans translates randart option title")

	local zh_boss_desc = _t(ChnOptions.RAND_BOSS_DESC)
	local zh_art_desc = _t(ChnOptions.RAND_ART_DESC)
	check(zh_boss_desc ~= ChnOptions.RAND_BOSS_DESC and zh_boss_desc:find("历史战斗日志", 1, true) ~= nil, "zh_hans translates randboss option description including combat log note")
	check(zh_art_desc ~= ChnOptions.RAND_ART_DESC and zh_art_desc:find("随机神器", 1, true) ~= nil, "zh_hans translates randart option description")

	I18N:setLocale("en_US")
	check(_t("Localization") == "Localization", "en_US keeps 'Localization'")
	check(_t("#GOLD##{bold}#Chinese random boss names#WHITE##{normal}#") == "#GOLD##{bold}#Chinese random boss names#WHITE##{normal}#", "en_US randboss title is clean English without ##tag residue")
	check(_t("#GOLD##{bold}#Chinese random artifact names#WHITE##{normal}#") == "#GOLD##{bold}#Chinese random artifact names#WHITE##{normal}#", "en_US randart title is clean English without ##tag residue")
	check(not _t(ChnOptions.RAND_BOSS_DESC):find("##", 1, true), "en_US randboss desc has no ## residue")
	check(not _t(ChnOptions.RAND_ART_DESC):find("##", 1, true), "en_US randart desc has no ## residue")

	I18N:setLocale("zh_hans")
end

-- ============================================================================
-- 4. GameOptions:tabs + superload/mod/dialogs/GameOptions.lua integration test
-- ============================================================================
do
	string.capitalize = string.capitalize or function(s)
		return s:sub(1, 1):upper() .. s:sub(2)
	end
	string.toTString = function(s)
		return { __tstring = true, text = s }
	end

	local drawn_items = {}
	package.loaded["engine.ui.TreeList"] = {
		new = function(t)
			t.drawItem = function(self, item)
				table.insert(drawn_items, item)
			end
			return t
		end,
	}
	package.loaded["engine.ui.Textzone"] = {
		new = function(t) return t end,
	}

	local real_i18nhelper = real_dofile("overload/engine/i18nhelper.lua")
	local replace_format_calls = 0
	package.loaded["engine.i18nhelper"] = {
		replaceFormat = function(self, func)
			replace_format_calls = replace_format_calls + 1
			return real_i18nhelper:replaceFormat(func)
		end,
	}

	-- Load superload/mod/dialogs/GameOptions.lua on top of a base GameOptions table
	local base_GameOptions = {}
	_G.loadPrevious = function() return base_GameOptions end
	local SuperGameOptions = real_dofile("superload/mod/dialogs/GameOptions.lua")

	-- Install chn_options hooks (and verify idempotence on repeated install)
	local cls = package.loaded["engine.class"]
	check(ChnOptions.install(cls) == true, "ChnOptions.install succeeded")
	check(ChnOptions.install(cls) == true, "ChnOptions.install is idempotent")
	check(#(cls._hook_registry["GameOptions:tabs"] or {}) == 1, "GameOptions:tabs bound exactly once")
	check(#(cls._hook_registry["Game:changeLevel"] or {}) == 1, "Game:changeLevel bound exactly once")

	-- Simulate GameOptions:init()
	local saved_settings = {}
	_G.game = {
		saveSettings = function(self, k, v) saved_settings[k] = v end,
		player = { changed = false },
		level = { map = { changed = false } },
	}
	config.settings = { locale = "zh_hans", chn_mod = { randboss_names = true, randart_names = true } }

	local dialog = setmetatable({
		iw = 800,
		ih = 600,
		vsep = { w = 10 },
		c_desc = { w = 390, h = 600 },
		list = {},
		triggerHook = function(self, data)
			cls:triggerHook(data)
		end,
		select = function(self, item) end,
		replaceUI = function(self, old_ui, new_ui) end,
	}, { __index = SuperGameOptions })

	local tabs = {
		{ title = _t"UI", kind = "ui" },
		{ title = _t"Gameplay", kind = "gameplay" },
		{ title = _t"Online", kind = "online" },
		{ title = _t"Misc", kind = "misc" },
	}
	dialog:triggerHook{"GameOptions:tabs", tab = function(title, fct)
		local id = #tabs + 1
		tabs[id] = { title = title, kind = "hooktab" .. id }
		dialog["generateListHooktab" .. id] = fct
	end}

	check(#tabs == 5, "Localization tab appended as 5th tab")
	check(tabs[5].title == "汉化" and tabs[5].kind == "hooktab5", "5th tab title is '汉化' and kind is 'hooktab5'")
	check(type(dialog.generateListHooktab5) == "function", "generateListHooktab5 registered on dialog")

	-- Switch to hooktab5 using superload switchTo
	replace_format_calls = 0
	dialog:switchTo("hooktab5")
	check(replace_format_calls == 0, "switchTo('hooktab5') does not double-wrap status with i18nhelper:replaceFormat")
	check(#dialog.list == 2, "Localization tab has 2 option items")

	local item_boss = dialog.list[1]
	local item_art = dialog.list[2]
	check(type(item_boss.name) == "table" and item_boss.name.text == "#GOLD##{bold}#随机怪物中文命名#WHITE##{normal}#", "item 1 name translated TString")
	check(type(item_art.name) == "table" and item_art.name.text == "#GOLD##{bold}#随机神器中文命名#WHITE##{normal}#", "item 2 name translated TString")
	check(item_boss.status() == "已启用", "item 1 initial status is '已启用'")
	check(item_art.status() == "已启用", "item 2 initial status is '已启用'")

	-- Toggle item 1 (randboss) off and back on
	item_boss.fct(item_boss)
	check(ChnOptions.is_randboss_enabled() == false, "clicking item 1 disables randboss_names")
	check(ChnOptions.is_randart_enabled() == true, "clicking item 1 does not affect randart_names")
	check(item_boss.status() == "已禁用", "item 1 status updated to '已禁用'")
	check(saved_settings["chn_mod.randboss_names"] == "chn_mod.randboss_names = false\n", "item 1 persisted false")
	check(drawn_items[#drawn_items] == item_boss, "drawItem called for item 1")
	check(_G.game.player.changed == true and _G.game.level.map.changed == true, "player and map marked changed")

	-- Toggle item 2 (randart) off
	_G.game.player.changed = false
	_G.game.level.map.changed = false
	item_art.fct(item_art)
	check(ChnOptions.is_randart_enabled() == false, "clicking item 2 disables randart_names")
	check(ChnOptions.is_randboss_enabled() == false, "randboss_names remains false")
	check(item_art.status() == "已禁用", "item 2 status updated to '已禁用'")
	check(saved_settings["chn_mod.randart_names"] == "chn_mod.randart_names = false\n", "item 2 persisted false")
	check(drawn_items[#drawn_items] == item_art, "drawItem called for item 2")
	check(_G.game.player.changed == true and _G.game.level.map.changed == true, "player and map marked changed on item 2")

	-- Toggle both back on
	item_boss.fct(item_boss)
	item_art.fct(item_art)
	check(ChnOptions.is_randboss_enabled() == true and ChnOptions.is_randart_enabled() == true, "both toggles re-enabled")
	check(item_boss.status() == "已启用" and item_art.status() == "已启用", "both statuses back to '已启用'")
end

-- ============================================================================
-- 5. Bidirectional dynamic switching for random bosses
-- ============================================================================
do
	-- Set up _t and string.tformat for boss naming templates
	local base_tr = {
		["skeleton warrior"] = "骷髅战士",
		["elven mage"] = "精灵法师",
		["orc berserker"] = "兽人狂战士",
		["%s the %s"] = "%2$s%1$s",
	}
	local i18n_t = _G._t
	_G._t = function(s, tag)
		if config.settings.locale == "zh_hans" and base_tr[s] then
			return base_tr[s]
		end
		return i18n_t(s, tag)
	end
	string.tformat = function(s, a, b)
		if s == "%s the %s" and config.settings.locale == "zh_hans" then
			return tostring(b) .. tostring(a)
		end
		return string.format(s, a, b)
	end

	local function make_boss(orig_name, base_name, rank)
		return {
			randboss = true,
			name = orig_name,
			unique = orig_name,
			define_as = "RND_BOSS_" .. (orig_name:upper():gsub("[^A-Z]", "_")),
			rank = rank or 3.2,
		}, {
			name = base_name,
			type = "undead",
			subtype = "skeleton",
		}
	end

	local state = {}
	config.settings = { locale = "zh_hans", chn_mod = { randboss_names = true, randart_names = true } }

	-- 5a. Generated while enabled -> toggle off -> toggle on across all entity containers
	local b1, base1 = make_boss("骷髅战士Aluin", "skeleton warrior", 3.2)
	local b2, base2 = make_boss("骷髅战士Borin", "skeleton warrior", 3.5)
	local b3, base3 = make_boss("骷髅战士Cael", "skeleton warrior", 3.2)
	local b4, base4 = make_boss("骷髅战士Doran", "skeleton warrior", 3.2)
	local b5, base5 = make_boss("骷髅战士Elric", "skeleton warrior", 3.2)
	local b6, base6 = make_boss("骷髅战士Faelan", "skeleton warrior", 3.2)

	for _, pair in ipairs{{b1, base1}, {b2, base2}, {b3, base3}, {b4, base4}, {b5, base5}, {b6, base6}} do
		BossNames.rename(pair[1], pair[2], {}, state)
		check(pair[1].name ~= pair[1].unique and pair[1].name == pair[1].__chn_randboss_name.text, "boss renamed when enabled: " .. tostring(pair[1].name))
	end

	-- Place bosses in all 6 container locations (with duplicates across containers to test deduplication)
	_G.__uids = { [101] = b1, [102] = b2 }
	_G.game = {
		state = state,
		player = { changed = false },
		level = {
			map = { changed = false },
			entities = { [101] = b1, [103] = b3 },
		},
		party = {
			members = {
				[b4] = { control = "full" },
				[b1] = { control = "order" }, -- duplicate of b1
			},
		},
		zone = {
			memory_levels = {
				[1] = { entities = { [105] = b5 } },
			},
			temp_memory_levels = {
				[2] = { entities = { [106] = b6 } },
			},
		},
		memory_levels = {
			["old-zone"] = {
				[1] = { entities = { [105] = b5, [102] = b2 } },
			},
		},
		saveSettings = function() end,
	}

	-- Disable randboss_names -> all 6 unique bosses revert to original names
	ChnOptions.set_randboss_enabled(false, _G.game)
	for idx, b in ipairs{b1, b2, b3, b4, b5, b6} do
		check(b.name == b.__chn_randboss_name.original, "boss " .. idx .. " dynamically reverted to original name: " .. tostring(b.name))
	end
	-- Calling sync_all again when already reverted returns 0 changed
	check(BossNames.sync_all(_G.game) == 0, "sync_all returns 0 when all bosses already match disabled state")

	-- Re-enable randboss_names -> all 6 unique bosses restore their Chinese names
	local changed_on = BossNames.sync_all(_G.game)
	check(changed_on == 0, "before flag flip, sync_all is 0")
	ChnOptions.set_randboss_enabled(true, _G.game)
	for idx, b in ipairs{b1, b2, b3, b4, b5, b6} do
		check(b.name == b.__chn_randboss_name.text, "boss " .. idx .. " dynamically restored to Chinese name: " .. tostring(b.name))
	end

	-- 5b. Generated while disabled -> keeps original name, records metadata & ledger, idempotent on re-rename, switches on enable
	ChnOptions.set_randboss_enabled(false, _G.game)
	local count_before = state.__chn_randboss_ledger.count
	local b_off, base_off = make_boss("骷髅战士Garrick", "skeleton warrior", 3.5)
	BossNames.rename(b_off, base_off, {}, state)
	local meta_off = rawget(b_off, "__chn_randboss_name")
	check(type(meta_off) == "table", "boss generated while disabled still gets __chn_randboss_name metadata")
	check(b_off.name == "骷髅战士Garrick", "boss generated while disabled keeps original b.name")
	check(meta_off.original == "骷髅战士Garrick", "meta.original stores original name")
	check(type(meta_off.text) == "string" and meta_off.text ~= "" and meta_off.text ~= meta_off.original, "meta.text stores pre-allocated Chinese name: " .. tostring(meta_off.text))
	check(state.__chn_randboss_ledger.count == count_before + 1, "ledger recorded core for boss generated while disabled")

	-- Idempotence check: calling M.rename again while disabled must not re-allocate or increment ledger
	local pre_text = meta_off.text
	BossNames.rename(b_off, base_off, {}, state)
	check(state.__chn_randboss_ledger.count == count_before + 1, "repeated M.rename while disabled does not double-count ledger")
	check(b_off.__chn_randboss_name.text == pre_text and b_off.name == "骷髅战士Garrick", "repeated M.rename while disabled is a no-op")

	-- Register b_off in level entities and enable randboss_names
	_G.game.level.entities[107] = b_off
	ChnOptions.set_randboss_enabled(true, _G.game)
	check(b_off.name == pre_text, "boss generated while disabled immediately switches to its Chinese name when enabled")
	ChnOptions.set_randboss_enabled(false, _G.game)
	check(b_off.name == "骷髅战士Garrick", "boss reverts back to original name when disabled again")
	ChnOptions.set_randboss_enabled(true, _G.game)
	check(b_off.name == pre_text, "boss restores Chinese name again")

	-- 5c. Custom / quest rename protection & safety checks
	b1.name = "特殊任务首领"
	check(BossNames.sync_actor(b1) == false and b1.name == "特殊任务首领", "sync_actor never overwrites custom quest/addon renamed boss")
	ChnOptions.set_randboss_enabled(false, _G.game)
	check(b1.name == "特殊任务首领", "disabling randboss_names preserves custom quest/addon renamed boss")
	ChnOptions.set_randboss_enabled(true, _G.game)
	b1.name = b1.__chn_randboss_name.text -- restore for further tests

	local b_corrupt = {
		randboss = true,
		name = "骷髅战士X",
		unique = "骷髅战士Y", -- mismatch with meta.original
		__chn_randboss_name = { text = "骷髅战士玄冥", original = "骷髅战士X" },
	}
	check(BossNames.sync_actor(b_corrupt) == false and b_corrupt.name == "骷髅战士X", "sync_actor ignores actor whose unique ~= meta.original")
	check(BossNames.sync_actor({ randboss = false, name = "普通怪" }) == false, "sync_actor ignores non-randboss")
	check(BossNames.sync_actor(nil) == false, "sync_actor safely handles nil")

	-- 5d. Real superload/mod/class/NPC.lua _M:loaded() test (including V1/V1.1 saved boss and locale switch)
	local base_NPC = {
		doEmote = function(self, text) return text end,
		loaded = function(self, a, b)
			self._base_loaded_called = true
			return "loaded_ok", a, b
		end,
	}
	_G.loadPrevious = function() return base_NPC end
	local SuperNPC = real_dofile("superload/mod/class/NPC.lua")

	local saved_boss = setmetatable({
		randboss = true,
		name = b2.__chn_randboss_name.text,
		unique = b2.__chn_randboss_name.original,
		__chn_randboss_name = {
			version = 1,
			text = b2.__chn_randboss_name.text,
			original = b2.__chn_randboss_name.original,
			core = b2.__chn_randboss_name.core,
			tier = "epic",
			culture = "undead",
			sex = "none",
			recorded = true,
		},
	}, { __index = SuperNPC })

	-- Load while disabled -> automatically reverts to original
	ChnOptions.set_randboss_enabled(false, _G.game)
	local r1, r2, r3 = saved_boss:loaded(10, 20)
	check(saved_boss._base_loaded_called == true and r1 == "loaded_ok" and r2 == 10 and r3 == 20, "NPC:loaded preserves original return values")
	check(saved_boss.name == saved_boss.__chn_randboss_name.original, "NPC:loaded reverts boss name when randboss_names is disabled")

	-- Load while enabled -> automatically restores Chinese name
	ChnOptions.set_randboss_enabled(true, _G.game)
	saved_boss:loaded()
	check(saved_boss.name == saved_boss.__chn_randboss_name.text, "NPC:loaded restores boss Chinese name when randboss_names is enabled")

	-- Load when locale is switched to en_US -> automatically reverts to original name
	config.settings.locale = "en_US"
	saved_boss:loaded()
	check(saved_boss.name == saved_boss.__chn_randboss_name.original, "NPC:loaded reverts boss name when locale is en_US")
	config.settings.locale = "zh_hans"
	saved_boss:loaded()
	check(saved_boss.name == saved_boss.__chn_randboss_name.text, "NPC:loaded restores boss Chinese name when locale returns to zh_hans")

	-- 5e. Game:changeLevel hook test
	b3.name = b3.__chn_randboss_name.original -- simulate an unsynced entity on the newly entered level
	local cls = package.loaded["engine.class"]
	cls:triggerHook{"Game:changeLevel"}
	check(b3.name == b3.__chn_randboss_name.text, "Game:changeLevel hook automatically syncs entities on level change")
end

-- ============================================================================
-- 6. Bidirectional dynamic switching for random artifacts & independence test
-- ============================================================================
do
	local state = {}
	_G.game.state = state
	config.settings = { locale = "zh_hans", chn_mod = { randboss_names = true, randart_names = true } }

	local function make_randart(orig_name, unique_id, def_id)
		return {
			randart = true,
			name = orig_name,
			unique = unique_id,
			define_as = def_id,
			type = "weapon",
			subtype = "longsword",
			wielder = { inc_damage = { FIRE = 20 } },
			isIdentified = function() return true end,
		}
	end

	-- 6a. Generated while enabled -> decorate returns Chinese name -> disable returns original -> enable returns Chinese name
	local art1 = make_randart("Brotoq the Reaver", "Brotoq the Reaver", "RANDART_BROTOQ_1")
	ArtNames.annotate(art1, package.loaded["engine.DamageType"], state)
	local rendered_orig1 = "真龙长剑 Brotoq the Reaver (25-35 能量)"
	local dec_on1 = ArtNames.decorate(art1, nil, rendered_orig1, state)
	check(dec_on1 ~= rendered_orig1 and dec_on1:find("长剑「", 1, true) ~= nil, "randart decorated with Chinese name when enabled: " .. tostring(dec_on1))
	check(art1.__chn_randboss_name == nil and art1.__chn_randart_name.issued == true, "randart issued flag set to true")

	-- Disable randart_names (while keeping randboss_names enabled)
	ChnOptions.set_randart_enabled(false, _G.game)
	check(ChnOptions.is_randboss_enabled() == true and ChnOptions.is_randart_enabled() == false, "randart disabled while randboss remains enabled")
	local dec_off1 = ArtNames.decorate(art1, nil, rendered_orig1, state)
	check(dec_off1 == rendered_orig1, "randart immediately reverts to original rendered string when disabled")

	-- Re-enable randart_names -> immediately restores exact same Chinese name
	ChnOptions.set_randart_enabled(true, _G.game)
	local dec_on1_again = ArtNames.decorate(art1, nil, rendered_orig1, state)
	check(dec_on1_again == dec_on1, "randart immediately restores identical Chinese name when re-enabled")

	-- 6b. Generated while disabled -> annotate still records metadata without committing ledger, enabling later issues Chinese name
	ChnOptions.set_randart_enabled(false, _G.game)
	local ledger_count_before = state.__chn_randart_ledger.count
	local art2 = make_randart("Glamdring", "Glamdring", "RANDART_GLAMDRING_2")
	ArtNames.annotate(art2, package.loaded["engine.DamageType"], state)
	check(type(art2.__chn_randart_name) == "table" and art2.__chn_randart_name.original == "Glamdring", "randart generated while disabled still gets __chn_randart_name metadata")
	check(art2.__chn_randart_name.issued == false, "randart generated while disabled is not yet issued")
	local rendered_orig2 = "秘银长剑 Glamdring"
	check(ArtNames.decorate(art2, nil, rendered_orig2, state) == rendered_orig2, "decorate while disabled returns original string and does not commit ledger")
	check(state.__chn_randart_ledger.count == ledger_count_before, "ledger count unchanged while randart_names is disabled")

	-- Now enable randart_names -> art2 immediately displays Chinese name and commits to ledger
	ChnOptions.set_randart_enabled(true, _G.game)
	local dec_on2 = ArtNames.decorate(art2, nil, rendered_orig2, state)
	check(dec_on2 ~= rendered_orig2 and dec_on2:find("长剑「", 1, true) ~= nil, "randart generated while disabled displays Chinese name once enabled: " .. tostring(dec_on2))
	check(art2.__chn_randart_name.issued == true and state.__chn_randart_ledger.count == ledger_count_before + 1, "randart committed to ledger upon first enabled decorate")
end

print("ALL test_chn_options TESTS PASSED")
