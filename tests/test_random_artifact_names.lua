-- Run from the addon root with Lua 5.1 or LuaJIT.
-- Optional arg (or TOME_OBJECT_LUA): extracted 1.7.6 mod/class/Object.lua to exercise its actual getName.
-- Optional env TOME_ZH_HANS_LUA / ADDON_ZH_HANS_LUA: explicit locale dictionary paths for entity name collision audit.
local real_dofile = dofile
dofile = function(path)
	if path == "/data-chn-mod/chn_random_names.lua" then path = "data/chn_random_names.lua" end
	if path == "/hooks/chn-mod/random_artifact_names.lua" then path = "hooks/random_artifact_names.lua" end
	return real_dofile(path)
end
config = { settings = { locale = "zh_hans" } }
local damage_types = {
	FIRE = "FIRE", COLD = "COLD", LIGHTNING = "LIGHTNING",
	LIGHT = "LIGHT", DARKNESS = "DARKNESS", ARCANE = "ARCANE", PHYSICAL = "PHYSICAL",
}
package.loaded["engine.DamageType"] = damage_types
local original_random = math.random
math.random = function() error("naming used math.random") end
rng = setmetatable({}, { __index = function() error("naming used the engine RNG") end })

local names = dofile("/hooks/chn-mod/random_artifact_names.lua")
local rules = dofile("/data-chn-mod/chn_random_names.lua")

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

-- 0. Full 66-cohort capacity, connector-collapsed core count (>= 5000), coprime stride,
--    and all 23 fixed bases x 6 pools collision audit against V1, ToME zh_hans.lua, and addon zh_hans.lua
local pool_names = { "neutral", "fire", "cold", "lightning", "light", "darkness" }
local family_names = { "blade", "blunt", "cleave", "ranged", "focus", "shield", "robe", "mail", "gear", "stride", "jewelry" }

local v1_titles = {}
for _, p in ipairs(pool_names) do
	local list = rules.legacy_v1_pools and rules.legacy_v1_pools[p] or {}
	for _, t in ipairs(list) do
		v1_titles[t] = true
	end
end

local fixed_entity_names = {}
local fixed_inner_titles = {}
local function load_entity_names(path)
	local f = io.open(path, "r")
	if not f then
		return 0, false
	end
	local count = 0
	for line in f:lines() do
		if line:find('"entity name"', 1, true) then
			for extracted in line:gmatch(',%s*"([^"]+)"%s*,%s*"entity name"') do
				fixed_entity_names[extracted] = true
				count = count + 1
				local inner = extracted:match("「(.-)」") or extracted:match("“(.-)”")
				if inner then
					fixed_inner_titles[inner] = true
				end
			end
		end
	end
	f:close()
	return count, true
end

local tome_zh_path = os.getenv("TOME_ZH_HANS_LUA") or "/workspace/t-engine4/game/modules/tome/data/locales/zh_hans.lua"
local addon_zh_path = os.getenv("ADDON_ZH_HANS_LUA") or "data/locales/zh_hans.lua"
local tome_zh_count, tome_zh_ok = load_entity_names(tome_zh_path)
local addon_zh_count, addon_zh_ok = load_entity_names(addon_zh_path)
assert(addon_zh_ok and addon_zh_count > 0, "addon locale dictionary required for collision audit: " .. tostring(addon_zh_path))
if os.getenv("TOME_ZH_HANS_LUA") then
	assert(tome_zh_ok and tome_zh_count > 0, "explicit TOME_ZH_HANS_LUA could not be loaded: " .. tostring(tome_zh_path))
end

local min_raw = math.huge
local min_norm = math.huge
local min_core = math.huge
local min_cohort = nil
local total_cohorts = 0
local cohort_title_map = {}

for _, p in ipairs(pool_names) do
	cohort_title_map[p] = {}
	for _, f in ipairs(family_names) do
		local audit = names.audit_cohort(p, f, "长剑")
		total_cohorts = total_cohorts + 1
		assert(
			gcd(names.PROBE_STRIDE, audit.raw_slots) == 1,
			string.format("stride %d not coprime with raw_slots %d for (%s,%s)", names.PROBE_STRIDE, audit.raw_slots, p, f)
		)
		assert(
			audit.core_count >= 5000,
			string.format("cohort (%s, %s) connector-collapsed core_count %d < 5000", p, f, audit.core_count)
		)
		assert(
			audit.normalized_count >= 12000,
			string.format("cohort (%s, %s) normalized_count %d < 12000", p, f, audit.normalized_count)
		)
		if audit.raw_slots < min_raw then min_raw = audit.raw_slots end
		if audit.normalized_count < min_norm then min_norm = audit.normalized_count end
		if audit.core_count < min_core then
			min_core = audit.core_count
			min_cohort = p .. ":" .. f
		end
		for i = 1, #audit.list do
			local title = audit.list[i]:match("「(.-)」")
			if title then
				cohort_title_map[p][title] = true
			end
		end
	end
end
assert(total_cohorts == 66, "expected 66 cohorts")

-- Audit all 23 fixed bases x 6 pools (138 base-pool combinations) against V1, plain entity names, and quoted inner titles
local base_pool_combinations = 0
local v1_collisions = 0
local fixed_full_collisions = 0
local fixed_title_collisions = 0

for typ, subs in pairs(rules.base_names) do
	for sub, base in pairs(subs) do
		local fam = assert(rules.families[typ] and rules.families[typ][sub], "missing family for " .. tostring(typ) .. "/" .. tostring(sub))
		for _, p in ipairs(pool_names) do
			base_pool_combinations = base_pool_combinations + 1
			local audit = names.audit_cohort(p, fam, base)
			assert(audit.core_count >= 5000, string.format("base %s (%s:%s) core_count %d < 5000", base, p, fam, audit.core_count))
			for i = 1, #audit.list do
				local full = audit.list[i]
				local title = full:match("「(.-)」")
				if title and v1_titles[title] then
					v1_collisions = v1_collisions + 1
				end
				if fixed_entity_names[full] or fixed_inner_titles[full] then
					fixed_full_collisions = fixed_full_collisions + 1
				end
				if title and (fixed_entity_names[title] or fixed_inner_titles[title]) then
					fixed_title_collisions = fixed_title_collisions + 1
				end
			end
		end
	end
end
assert(base_pool_combinations == 138, "expected 23 fixed bases x 6 pools = 138 combinations, got " .. tostring(base_pool_combinations))
assert(v1_collisions == 0, "expected 0 collisions with V1 legacy titles, got " .. tostring(v1_collisions))
assert(fixed_full_collisions == 0, "expected 0 full-name collisions with fixed entity names, got " .. tostring(fixed_full_collisions))
assert(fixed_title_collisions == 0, "expected 0 inner-title collisions with fixed entity names/titles, got " .. tostring(fixed_title_collisions))
assert(not cohort_title_map.lightning["风暴之刃"], "风暴之刃 must be explicitly excluded (Shantiz the Stormblade)")
assert(not cohort_title_map.lightning["风暴之怒"], "风暴之怒 must be explicitly excluded (Storm Fury)")

-- 0b. Subtype semantic compatibility audit across families
local forbidden_by_family = {
	blade = { "剑" },
	blunt = { "锤", "斧", "槌" },
	cleave = { "锤", "斧", "槌" },
	ranged = { "弓", "箭", "羽", "矢", "镝", "弦" },
	shield = { "盾" },
	robe = { "衣", "袍", "甲", "铠", "衫", "裳", "胄" },
	mail = { "衣", "袍", "甲", "铠", "衫", "裳", "胄" },
	gear = { "步", "足", "掌", "冠", "腰", "额", "顶", "靴", "履" },
	stride = { "掌", "冠", "腰", "额", "顶", "靴" },
}
for fam, bad_chars in pairs(forbidden_by_family) do
	local audit = names.audit_cohort("neutral", fam, "长剑")
	for _, full in ipairs(audit.list) do
		local title = full:match("「(.-)」") or ""
		for _, bc in ipairs(bad_chars) do
			assert(not title:find(bc, 1, true), string.format("family %s contains subtype-specific char %s in %s", fam, bc, full))
		end
	end
end

-- Set up GameState and Object superloads
local calls = 0
local state = {
	generateRandart = function(_, o, a, b)
		calls = calls + 1
		if a == "error" then error("stock generation error") end
		return o, a, b
	end,
}
_G.game = { state = state }
local function reset_ledger(custom_ledger)
	state.__chn_randart_ledger = custom_ledger
end

loadPrevious = function() return state end
dofile("superload/mod/class/GameState.lua")

local stock_getName_count = 0
local Object = {
	getTextualDesc = function() end,
	getNumber = function(self) return self.qty or 1 end,
	isIdentified = function(self) return self.identified end,
	getUnidentifiedName = function() return "未鉴定长剑" end,
	getDisplayColor = function() return {}, "#FFD700#" end,
	getDisplayString = function() return "!" end,
	descAttribute = function(_, key) assert(key == "COMBAT"); return "数值" end,
}
_t = function(s, tag)
	if tag == "entity add_name" and s == " (#COMBAT#)" then return "（#COMBAT#）" end
	if s == "Iron sword of mischance" and tag == "entity name" then return "倒霉的铁剑" end
	return s
end

local object_lua_arg = (arg and arg[1]) or os.getenv("TOME_OBJECT_LUA")
if object_lua_arg then
	local f = assert(io.open(object_lua_arg, "rb"))
	local s = f:read("*a")
	f:close()
	local first = assert(s:find("function _M:getName(t)", 1, true))
	local last = assert(s:find("\n--- Gets the short name", first, true))
	assert(loadstring("local _M = ...\n" .. s:sub(first, last - 1)))(Object)
else
	function Object:getName(t)
		t = t or {}
		local name = _t(self.name, "entity name")
		if t.trans_only then return name end
		if t.raw_name then return self.name end
		if not t.no_add_name then name = (self.been_reshaped or "") .. name end
		if not self.identified and not t.force_id then name = self:getUnidentifiedName() end
		if self.identified and self.add_name and not t.no_add_name then
			name = name .. self.add_name:gsub("#([^#]+)#", function(k) return self:descAttribute(k) end)
		end
		if t.do_color then name = (t.no_image and "" or "!") .. name end
		if self:getNumber() > 1 and not t.no_count then name = self:getNumber() .. " " .. name end
		if t.do_color then name = "#FFD700#" .. name .. "#LAST#" end
		return name
	end
end

local getName = Object.getName
Object.getName = function(self, t, ...)
	stock_getName_count = stock_getName_count + 1
	if t and t.fail then error("stock display error") end
	return getName(self, t, ...), nil, "third"
end
loadPrevious = function() return Object end
dofile("superload/mod/class/Object.lua")

local function artifact(extra)
	local o = {
		name = "Iron sword of mischance",
		define_as = "SWORD_TEST",
		unique = "Test sword",
		namescheme = "test",
		randart = true,
		identified = true,
		type = "weapon",
		subtype = "longsword",
	}
	for k, v in pairs(extra or {}) do o[k] = v end
	return setmetatable(o, { __index = Object })
end

-- 1. Core generation, pending annotation vs first identified display issuance
reset_ledger(nil)
local o = artifact{ wielder = { inc_damage = { [damage_types.FIRE] = 20 } }, add_name = " (#COMBAT#)", qty = 2, been_reshaped = "重塑" }
local result, hole, tail = state:generateRandart(o, nil, "stock tail")
assert(calls == 1 and result == o and hole == nil and tail == "stock tail")
assert(o.name == "Iron sword of mischance" and o.define_as == "SWORD_TEST"
	and o.unique == "Test sword" and o.namescheme == "test")
local meta = assert(o.__chn_randart_name)
assert(meta.version == 2 and meta.issued == false and meta.pool == "fire" and meta.family == "blade")
assert(cohort_title_map.fire[meta.text:match("「(.-)」")])
assert(state.__chn_randart_ledger.count == 0, "generateRandart alone must not consume ledger capacity before display")

local output, blank, third = o:getName{ do_color = true }
assert(meta.issued == true, "first identified zh_hans getName must mark meta.issued = true")
assert(state.__chn_randart_ledger.count == 1 and state.__chn_randart_ledger.used[meta.text] == true)
assert(output == "#FFD700#2 !重塑" .. meta.text .. "（数值）#LAST#" and blank == nil and third == "third")
assert(stock_getName_count == 1 and o.add_name == " (#COMBAT#)")
assert(o:getName{ raw_name = true } == o.name)
assert(o:getName{ trans_only = true } == "倒霉的铁剑")
assert(o:getName{ no_add_name = true, no_count = true } == meta.text)
assert(state.__chn_randart_ledger.count == 1, "repeated getName on issued object must be idempotent")

o.identified = false
assert(not o:getName{ force_id = true }:find(meta.text, 1, true))
assert(o:getName{ no_count = true } == "未鉴定长剑")
o.identified = true
config.settings.locale = "en_US"
assert(not o:getName():find(meta.text, 1, true))
config.settings.locale = "zh_hans"
assert(o:getName():find(meta.text, 1, true))
assert(not pcall(o.getName, o, { fail = true }) and o.add_name == " (#COMBAT#)")
assert(not pcall(state.generateRandart, state, nil, "error"))
assert(state:generateRandart(nil) == nil)

-- 2. Clone equivalent to a saved/reloaded plain entity; no generator call.
local loaded = artifact()
loaded.__chn_randart_name = {}
for k, v in pairs(meta) do
	assert(type(v) == "string" or type(v) == "number" or type(v) == "boolean")
	loaded.__chn_randart_name[k] = v
end
assert(loaded:getName() == meta.text)
local same_after_load = state:generateRandart(artifact{ wielder = { inc_damage = { [damage_types.FIRE] = 20 } } })
assert(same_after_load.__chn_randart_name.text ~= meta.text, "new object with same hash must advance past reserved name")
assert(loaded:getName() == meta.text, "reloaded object must keep its issued name")
loaded.unique = "changed identity"
assert(loaded:getName() == "倒霉的铁剑")
assert(artifact():getName() == "倒霉的铁剑")
assert(not state:generateRandart(artifact{ randart = false }).__chn_randart_name)
assert(not state:generateRandart(artifact{ subtype = "mod-unknown" }).__chn_randart_name)

-- 3. Elemental equipment via wielder.inc_damage (each supported element + unsupported/invalid/zero/negative).
for _, case in ipairs{
	{ "fire", { wielder = { inc_damage = { [damage_types.FIRE] = 15 } } } },
	{ "cold", { wielder = { inc_damage = { [damage_types.COLD] = 12 } } } },
	{ "lightning", { wielder = { inc_damage = { [damage_types.LIGHTNING] = 18 } } } },
	{ "light", { wielder = { inc_damage = { [damage_types.LIGHT] = 10 } } } },
	{ "darkness", { wielder = { inc_damage = { [damage_types.DARKNESS] = 22 } } } },
	{ "neutral", { wielder = { inc_damage = { [damage_types.ARCANE] = 25, all = 10 } } } },
	{ "neutral", { wielder = { inc_damage = { [damage_types.FIRE] = 0 } } } },
	{ "neutral", { wielder = { inc_damage = { [damage_types.COLD] = -5 } } } },
	{ "neutral", { wielder = { inc_damage = { [damage_types.LIGHTNING] = "15" } } } },
	{ "neutral", { inc_damage = { [damage_types.FIRE] = 20 } } },
} do
	local item = state:generateRandart(artifact(case[2]))
	assert(item.__chn_randart_name.pool == case[1])
	assert(cohort_title_map[case[1]][item.__chn_randart_name.text:match("「(.-)」")])
end

-- 4. Real 1.7.6 staff shapes: combat.element + commandStaff wielder.inc_damage (no double counting).
local fire_staff = state:generateRandart(artifact{
	subtype = "staff",
	combat = { dam = 15, damtype = damage_types.PHYSICAL, element = damage_types.FIRE },
	wielder = { inc_damage = { [damage_types.FIRE] = 15 } },
})
assert(fire_staff.__chn_randart_name.pool == "fire" and fire_staff.__chn_randart_name.family == "focus")
assert(cohort_title_map.fire[fire_staff.__chn_randart_name.text:match("「(.-)」")])

local arcane_cold_staff = state:generateRandart(artifact{
	subtype = "staff",
	combat = { dam = 15, damtype = damage_types.PHYSICAL, element = damage_types.ARCANE },
	wielder = { inc_damage = { [damage_types.ARCANE] = 15, [damage_types.COLD] = 10 } },
})
assert(arcane_cold_staff.__chn_randart_name.pool == "cold" and arcane_cold_staff.__chn_randart_name.family == "focus")

local greater_staff = state:generateRandart(artifact{
	subtype = "staff",
	combat = { dam = 15, damtype = damage_types.PHYSICAL, element = damage_types.FIRE, is_greater = true },
	wielder = { inc_damage = {
		[damage_types.FIRE] = 15, [damage_types.COLD] = 15,
		[damage_types.LIGHTNING] = 15, [damage_types.ARCANE] = 15,
	} },
})
assert(greater_staff.__chn_randart_name.pool == "neutral")

local mixed = state:generateRandart(artifact{
	wielder = { inc_damage = { [damage_types.FIRE] = 20, [damage_types.COLD] = 20 } },
})
assert(mixed.__chn_randart_name.pool == "neutral")

local single_pos = state:generateRandart(artifact{
	wielder = { inc_damage = { [damage_types.LIGHT] = 12, [damage_types.DARKNESS] = -5, [damage_types.FIRE] = 0 } },
})
assert(single_pos.__chn_randart_name.pool == "light")

-- 5. Old saved V1 metadata is never recomputed even if live elemental fields change after load.
local old_saved = artifact{ wielder = { inc_damage = { [damage_types.FIRE] = 30 } } }
old_saved.__chn_randart_name = {
	version = 1, text = "长剑「旅人的信物」",
	original = old_saved.name, unique = old_saved.unique, define_as = old_saved.define_as,
}
assert(state:generateRandart(old_saved).__chn_randart_name.text == "长剑「旅人的信物」")
assert(old_saved:getName() == "长剑「旅人的信物」")

-- 6. Rendering fallback checks BEFORE ledger registration (non-plain original, missing original, duplicate original)
reset_ledger(nil)
local unrendered_item = state:generateRandart(artifact{
	unique = "Unrendered_Sword",
	define_as = "RANDART_UNRENDERED",
})
assert(unrendered_item.__chn_randart_name.issued == false)
-- 6a. Duplicate occurrence in rendered string -> falls back without registering or marking issued
assert(names.decorate(unrendered_item, {}, "倒霉的铁剑和倒霉的铁剑") == "倒霉的铁剑和倒霉的铁剑")
assert(unrendered_item.__chn_randart_name.issued == false, "ambiguous duplicate rendering must not mark item issued")
assert(state.__chn_randart_ledger == nil or state.__chn_randart_ledger.count == 0, "ambiguous duplicate rendering must not consume ledger")

-- 6b. Missing original in rendered string -> falls back without registering or marking issued
assert(names.decorate(unrendered_item, {}, "完全无关的渲染文本") == "完全无关的渲染文本")
assert(unrendered_item.__chn_randart_name.issued == false, "missing original in rendering must not mark item issued")
assert(state.__chn_randart_ledger == nil or state.__chn_randart_ledger.count == 0, "missing original in rendering must not consume ledger")

-- 6c. Non-plain translated original (e.g. containing color/control markup '#') -> falls back without registering or marking issued
local old_t_fn = _G._t
_G._t = function(s, tag)
	if s == "Iron sword of mischance" and tag == "entity name" then return "#FFD700#倒霉的铁剑#LAST#" end
	return old_t_fn(s, tag)
end
assert(names.decorate(unrendered_item, {}, "#FFD700#倒霉的铁剑#LAST#") == "#FFD700#倒霉的铁剑#LAST#")
_G._t = old_t_fn
assert(unrendered_item.__chn_randart_name.issued == false, "non-plain translated original must not mark item issued")
assert(state.__chn_randart_ledger == nil or state.__chn_randart_ledger.count == 0, "non-plain translated original must not consume ledger")

-- 6d. Subsequent normal rendering on the same item now succeeds, registers, and solidifies
local valid_render = unrendered_item:getName{ no_add_name = true, no_count = true }
assert(valid_render == unrendered_item.__chn_randart_name.text)
assert(unrendered_item.__chn_randart_name.issued == true)
assert(state.__chn_randart_ledger.count == 1)

-- 7. Stress Test A: 1,000 mixed objects in one save -> 1,000 distinct final displayed names (0 duplicates)
reset_ledger(nil)
local subtypes_list = {
	{ type = "weapon", subtype = "longsword" },
	{ type = "weapon", subtype = "battleaxe" },
	{ type = "weapon", subtype = "longbow" },
	{ type = "weapon", subtype = "staff" },
	{ type = "armor", subtype = "shield" },
	{ type = "armor", subtype = "heavy" },
	{ type = "armor", subtype = "feet" },
	{ type = "jewelry", subtype = "ring" },
}
local elems_list = { nil, "FIRE", "COLD", "LIGHTNING", "LIGHT", "DARKNESS" }
local seen_mixed = {}
local mixed_unique_count = 0
for i = 1, 1000 do
	local st = subtypes_list[((i - 1) % #subtypes_list) + 1]
	local el = elems_list[((i - 1) % #elems_list) + 1]
	local item = state:generateRandart(artifact{
		type = st.type,
		subtype = st.subtype,
		unique = "MixedUnique_" .. tostring(i),
		define_as = "RANDART_MIX_" .. tostring(i),
		uid = 1000 + i,
		wielder = el and { inc_damage = { [damage_types[el]] = 10 } } or nil,
	})
	local disp = item:getName{ no_add_name = true, no_count = true }
	assert(disp ~= "倒霉的铁剑" and disp:find("「", 1, true), "expected issued V2 name for mixed item #" .. tostring(i))
	assert(item.__chn_randart_name.issued == true)
	if not seen_mixed[disp] then
		seen_mixed[disp] = true
		mixed_unique_count = mixed_unique_count + 1
	end
end
assert(mixed_unique_count == 1000, "expected 1000 unique final displayed names in mixed run, got " .. tostring(mixed_unique_count))
assert(state.__chn_randart_ledger.count == 1000)

-- 8. Stress Test B: 1,000 distinct objects with IDENTICAL hash, unique, define_as, and uid on a single fixed base (smallest cohort lightning:ranged)
reset_ledger(nil)
local seen_collision = {}
local collision_unique_count = 0
for i = 1, 1000 do
	local item = state:generateRandart(artifact{
		type = "weapon",
		subtype = "longbow",
		unique = "Identical Bow",
		define_as = "RANDART_SAME_BOW",
		uid = 2665,
		wielder = { inc_damage = { [damage_types.LIGHTNING] = 15 } },
	})
	local disp = item:getName{ no_add_name = true, no_count = true }
	assert(disp ~= "倒霉的铁剑" and disp:find("长弓「", 1, true), "expected issued V2 name on collision item #" .. tostring(i))
	assert(item.__chn_randart_name.issued == true)
	if not seen_collision[disp] then
		seen_collision[disp] = true
		collision_unique_count = collision_unique_count + 1
	end
end
assert(
	collision_unique_count == 1000,
	"expected 1000 unique final displayed names across 1000 identical-hash/UID objects, got " .. tostring(collision_unique_count)
)
assert(state.__chn_randart_ledger.count == 1000)

-- 9. Save/Reload + Same-UID New Object after reload
reset_ledger(nil)
local first_uid_item = state:generateRandart(artifact{
	unique = "Reload Collision Sword",
	define_as = "RANDART_RELOAD_1",
	uid = 2665,
	wielder = { inc_damage = { [damage_types.FIRE] = 20 } },
})
local first_uid_disp = first_uid_item:getName{ no_add_name = true, no_count = true }
assert(first_uid_disp:find("长剑「", 1, true) and first_uid_item.__chn_randart_name.issued == true)

-- Simulate save & reload of ledger + first_uid_item
local saved_ledger = {
	version = state.__chn_randart_ledger.version,
	count = state.__chn_randart_ledger.count,
	used = {},
}
for k, v in pairs(state.__chn_randart_ledger.used) do saved_ledger.used[k] = v end
reset_ledger(saved_ledger)

local reloaded_uid_item = artifact{
	unique = "Reload Collision Sword",
	define_as = "RANDART_RELOAD_1",
	uid = 2665,
	wielder = { inc_damage = { [damage_types.FIRE] = 20 } },
}
reloaded_uid_item.__chn_randart_name = {}
for k, v in pairs(first_uid_item.__chn_randart_name) do reloaded_uid_item.__chn_randart_name[k] = v end
assert(reloaded_uid_item:getName{ no_add_name = true, no_count = true } == first_uid_disp)

-- Now generate a brand-new item after reload that reuses the exact same uid, unique, and define_as
local new_same_uid_item = state:generateRandart(artifact{
	unique = "Reload Collision Sword",
	define_as = "RANDART_RELOAD_1",
	uid = 2665,
	wielder = { inc_damage = { [damage_types.FIRE] = 20 } },
})
local new_same_uid_disp = new_same_uid_item:getName{ no_add_name = true, no_count = true }
assert(new_same_uid_disp:find("长剑「", 1, true))
assert(new_same_uid_disp ~= first_uid_disp, "new item reusing UID/identity after reload must NOT receive the already-issued V2 name")
assert(reloaded_uid_item:getName{ no_add_name = true, no_count = true } == first_uid_disp, "reloaded item must retain its own issued V2 name")
assert(state.__chn_randart_ledger.count == 2)

-- 10. Elemental Cohort Exhaustion -> Neutral Fallback -> Stock Fallback (Never re-issues a used V2 name!)
local fire_blade_audit = names.audit_cohort("fire", "blade", "长剑")
local neutral_blade_audit = names.audit_cohort("neutral", "blade", "长剑")
local exhaust_used = {}
for i = 1, #fire_blade_audit.list - 1 do
	exhaust_used[fire_blade_audit.list[i]] = true
end
local last_fire_name = fire_blade_audit.list[#fire_blade_audit.list]
reset_ledger({ version = 2, count = 10, used = exhaust_used })

local last_fire_item = state:generateRandart(artifact{
	unique = "Last Fire Sword",
	define_as = "RANDART_LAST_FIRE",
	wielder = { inc_damage = { [damage_types.FIRE] = 25 } },
})
assert(last_fire_item:getName{ no_add_name = true, no_count = true } == last_fire_name)
assert(last_fire_item.__chn_randart_name.pool == "fire")

-- Next fire sword must fall back to neutral:blade
local overflow_fire_item = state:generateRandart(artifact{
	unique = "Overflow Fire Sword",
	define_as = "RANDART_OVERFLOW_FIRE",
	wielder = { inc_damage = { [damage_types.FIRE] = 25 } },
})
local overflow_disp = overflow_fire_item:getName{ no_add_name = true, no_count = true }
assert(overflow_disp:find("长剑「", 1, true) and overflow_fire_item.__chn_randart_name.pool == "neutral")
assert(cohort_title_map.neutral[overflow_disp:match("「(.-)」")])

-- Now exhaust all neutral:blade names too -> next fire sword must fall back to stock display ("倒霉的铁剑")
for i = 1, #neutral_blade_audit.list do
	state.__chn_randart_ledger.used[neutral_blade_audit.list[i]] = true
end
local totally_exhausted_item = state:generateRandart(artifact{
	unique = "Exhausted Fire Sword",
	define_as = "RANDART_EXHAUSTED_FIRE",
	wielder = { inc_damage = { [damage_types.FIRE] = 25 } },
})
assert(
	totally_exhausted_item:getName{ no_add_name = true, no_count = true } == "倒霉的铁剑",
	"when both elemental and neutral cohorts are exhausted, must fall back to stock display"
)
assert(totally_exhausted_item.__chn_randart_name.issued == false)

-- 11. Ledger MAX_LEDGER (8192) Capacity Boundary & 8193th Item Stock Fallback
reset_ledger(nil)
local cap_seen = {}
for i = 1, names.MAX_LEDGER do
	local st = subtypes_list[((i - 1) % #subtypes_list) + 1]
	local el = elems_list[((i - 1) % #elems_list) + 1]
	local item = state:generateRandart(artifact{
		type = st.type,
		subtype = st.subtype,
		unique = "CapUnique_" .. tostring(i),
		define_as = "RANDART_CAP_" .. tostring(i),
		uid = 20000 + i,
		wielder = el and { inc_damage = { [damage_types[el]] = 10 } } or nil,
	})
	local disp = item:getName{ no_add_name = true, no_count = true }
	assert(disp ~= "倒霉的铁剑" and disp:find("「", 1, true))
	assert(not cap_seen[disp], "duplicate V2 name before 8192 boundary at #" .. tostring(i))
	cap_seen[disp] = true
end
assert(state.__chn_randart_ledger.count == 8192)

local item_8193 = state:generateRandart(artifact{
	unique = "CapUnique_8193",
	define_as = "RANDART_CAP_8193",
	uid = 99999,
})
assert(item_8193:getName{ no_add_name = true, no_count = true } == "倒霉的铁剑", "8193th item must fall back to stock display")
assert(item_8193.__chn_randart_name.issued == false)
assert(state.__chn_randart_ledger.count == 8192)

-- Also verify an item annotated while unidentified before capacity is reached, then identified after capacity is 8192
reset_ledger(nil)
local pre_unid = state:generateRandart(artifact{
	identified = false,
	unique = "PreUnid_8193",
	define_as = "RANDART_PREUNID_8193",
})
assert(pre_unid.__chn_randart_name.issued == false and pre_unid.__chn_randart_name.text ~= "")
state.__chn_randart_ledger.count = 8192
pre_unid.identified = true
assert(pre_unid:getName{ no_add_name = true, no_count = true } == "倒霉的铁剑", "unissued item identified after ledger reaches 8192 must fall back to stock")
assert(pre_unid.__chn_randart_name.issued == false)

-- 12. Future Version / Corrupted Ledger Safety: never overwrite unknown ledger, unissued items fall back to stock, issued items still render
local future_ledger = { version = 99, count = 123, used = { keep_me = true }, custom_future_field = "do_not_clobber" }
reset_ledger(future_ledger)
local unissued_future = state:generateRandart(artifact{
	unique = "FutureLedgerSword",
	define_as = "RANDART_FUTURE_1",
})
assert(unissued_future:getName{ no_add_name = true, no_count = true } == "倒霉的铁剑")
assert(unissued_future.__chn_randart_name.issued == false)
assert(state.__chn_randart_ledger == future_ledger and future_ledger.version == 99 and future_ledger.custom_future_field == "do_not_clobber")

local already_issued = artifact{
	unique = "AlreadyIssuedOnFuture",
	define_as = "RANDART_ISSUED_FUTURE",
}
already_issued.__chn_randart_name = {
	version = 2,
	issued = true,
	text = "长剑「古旧之锋芒」",
	pool = "neutral",
	family = "blade",
	original = already_issued.name,
	unique = already_issued.unique,
	define_as = already_issued.define_as,
}
assert(already_issued:getName{ no_add_name = true, no_count = true } == "长剑「古旧之锋芒」")

reset_ledger("corrupted_non_table_ledger")
local unissued_corrupt = state:generateRandart(artifact{
	unique = "CorruptLedgerSword",
	define_as = "RANDART_CORRUPT_1",
})
assert(unissued_corrupt:getName{ no_add_name = true, no_count = true } == "倒霉的铁剑")
assert(state.__chn_randart_ledger == "corrupted_non_table_ledger")

math.random = original_random
local dict_status = string.format(
	"dicts=addon(%d)+tome(%s)",
	addon_zh_count,
	tome_zh_ok and tostring(tome_zh_count) or "SKIPPED"
)

-- 13. 3-char prefixes/nouns must never use empty connector ""
local function utf8_len(str)
	local n, i = 0, 1
	while i <= #str do
		local b = str:byte(i)
		i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
		n = n + 1
	end
	return n
end
local saw_three_char_prefix = false
local saw_three_char_noun = false
for _, p in ipairs(pool_names) do
	for _, pref in ipairs(rules.prefixes[p]) do
		if utf8_len(pref) == 3 then saw_three_char_prefix = true end
	end
end
for _, f in ipairs(family_names) do
	for _, n in ipairs(rules.nouns_2[f]) do
		if utf8_len(n) == 3 then saw_three_char_noun = true end
	end
end
assert(saw_three_char_prefix and saw_three_char_noun, "expected 3-char phrases in both prefixes and nouns_2")
for _, p in ipairs(pool_names) do
	for _, f in ipairs(family_names) do
		local audit = names.audit_cohort(p, f, "长剑")
		for i = 1, #audit.list do
			local title = audit.list[i]:match("「(.-)」")
			if not title:find("之", 1, true) and not title:find("的", 1, true) then
				assert(utf8_len(title) <= 4, "unseparated title exceeds 4 chars: " .. title)
			end
		end
	end
end

print(string.format(
	"random artifact naming V2 tests passed (cohorts=%d, base_pools=%d, min_raw=%d, min_norm=%d, min_core=%d [%s], %s)",
	total_cohorts, base_pool_combinations, min_raw, min_norm, min_core, tostring(min_cohort), dict_status
))
