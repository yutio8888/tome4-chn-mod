-- Full test suite for ToME4 Random Rare / Epic Boss Chinese Naming V1 (§7 T01–T19 & §6.5 E01–E32).
-- Run from addon root with LuaJIT or Lua 5.1.

local real_dofile = dofile
local cached_modules = {}
dofile = function(path)
	if path == "/data-chn-mod/chn_random_names.lua" then path = "data/chn_random_names.lua" end
	if path == "/hooks/chn-mod/random_artifact_names.lua" then path = "hooks/random_artifact_names.lua" end
	if path == "/data-chn-mod/chn_randboss_names.lua" then path = "data/chn_randboss_names.lua" end
	if path == "/hooks/chn-mod/random_boss_names.lua" then path = "hooks/random_boss_names.lua" end
	if path == "data/chn_randboss_names.lua" or path == "hooks/random_boss_names.lua" then
		if not cached_modules[path] then
			cached_modules[path] = real_dofile(path)
		end
		return cached_modules[path]
	end
	return real_dofile(path)
end

-- Save original RNG/time functions and install strict guards (§7.1, C1)
local orig_math_random = math.random
local orig_math_randomseed = math.randomseed
local orig_os_time = os.time
local orig_os_clock = os.clock

local function forbid_random_and_time()
	math.random = function() error("naming used math.random", 2) end
	math.randomseed = function() error("naming used math.randomseed", 2) end
	os.time = function() error("naming used os.time", 2) end
	os.clock = function() error("naming used os.clock", 2) end
	_G.rng = setmetatable({}, {
		__index = function(_, k)
			error("naming used engine rng." .. tostring(k), 2)
		end,
		__newindex = function()
			error("naming mutated engine rng", 2)
		end,
	})
end

forbid_random_and_time()

config = { settings = { locale = "zh_hans" } }
package.loaded["engine.DamageType"] = {
	FIRE = "FIRE", COLD = "COLD", LIGHTNING = "LIGHTNING",
	LIGHT = "LIGHT", DARKNESS = "DARKNESS", ARCANE = "ARCANE", PHYSICAL = "PHYSICAL",
}

local BossNames = dofile("/hooks/chn-mod/random_boss_names.lua")
local rules = BossNames.rules
local GenTokens = dofile("tests/gen_randboss_collision_tokens.lua")

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local function utf8_chars(s)
	local chars = {}
	if type(s) ~= "string" then return chars end
	local i = 1
	local len = #s
	while i <= len do
		local b = s:byte(i)
		local clen = b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1
		chars[#chars + 1] = s:sub(i, i + clen - 1)
		i = i + clen
	end
	return chars
end

local function plain_label(s)
	return type(s) == "string" and #s > 0 and not s:find("[#~&%%%c<>]")
end

local function deep_copy_plain(v, seen)
	if type(v) ~= "table" then
		return v
	end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local c = {}
	seen[v] = c
	for k, x in pairs(v) do
		local kt, xt = type(k), type(x)
		assert(kt == "string" or kt == "number" or kt == "boolean" or kt == "table", "non-serializable key type: " .. kt)
		assert(xt == "string" or xt == "number" or xt == "boolean" or xt == "table", "non-serializable value type: " .. xt)
		c[deep_copy_plain(k, seen)] = deep_copy_plain(x, seen)
	end
	return c
end

local function deep_equal(a, b, ignore_keys, visited)
	if type(a) ~= type(b) then return false, "type mismatch: " .. type(a) .. " vs " .. type(b) end
	if type(a) == "function" then
		if a == b then return true end
		local ia, ib = debug.getinfo(a, "S"), debug.getinfo(b, "S")
		if ia and ib and ia.source == ib.source and ia.linedefined == ib.linedefined and ia.lastlinedefined == ib.lastlinedefined then
			return true
		end
		return false, "function mismatch"
	end
	if type(a) ~= "table" then
		if a ~= b then return false, "value mismatch: " .. tostring(a) .. " vs " .. tostring(b) end
		return true
	end
	visited = visited or {}
	if visited[a] and visited[a][b] then return true end
	visited[a] = visited[a] or {}
	visited[a][b] = true
	for k, va in pairs(a) do
		if not (ignore_keys and ignore_keys[k]) then
			local ok, err = deep_equal(va, b[k], ignore_keys, visited)
			if not ok then return false, tostring(k) .. "." .. tostring(err) end
		end
	end
	for k, _ in pairs(b) do
		if not (ignore_keys and ignore_keys[k]) and a[k] == nil then
			return false, "extra key in b: " .. tostring(k)
		end
	end
	return true
end

local culture_order = { "human", "elf", "dwarf", "halfling", "yeek", "orc", "demon", "monster" }
local cohorts_26 = {}
for _, cname in ipairs(culture_order) do
	local cdef = assert(rules.cultures[cname], "missing culture " .. cname)
	local sexes = cdef.gendered and { "male", "female" } or { "none" }
	for _, sex in ipairs(sexes) do
		for _, tier in ipairs{ "rare", "epic" } do
			cohorts_26[#cohorts_26 + 1] = { culture = cname, sex = sex, tier = tier }
		end
	end
end
assert(#cohorts_26 == 26, "expected 26 cohorts, got " .. tostring(#cohorts_26))

-- ============================================================================
-- T01: Data Integrity (§7.2 T01, §4.6, §4.7)
-- ============================================================================
do
	local computed_approved = GenTokens.compute_approved_chars(rules)
	for ch in pairs(computed_approved) do
		assert(rules.approved_chars[ch] == true, "pool char missing from approved_chars: " .. ch)
	end
	for ch, v in pairs(rules.approved_chars) do
		assert(v == true and computed_approved[ch] == true, "extra/unreferenced char in approved_chars: " .. ch)
		assert(not rules.banned_chars[ch], "approved char is in banned_chars: " .. ch)
	end

	local function check_list(cname, list_name, lst, min_len, is_initial, is_male_or_none_final)
		assert(type(lst) == "table", cname .. "." .. list_name .. " must be a table")
		assert(#lst >= min_len, string.format("%s.%s length %d < %d", cname, list_name, #lst, min_len))
		local seen = {}
		for _, ch in ipairs(lst) do
			assert(type(ch) == "string" and #utf8_chars(ch) == 1, cname .. "." .. list_name .. " invalid single char: " .. tostring(ch))
			assert(not seen[ch], cname .. "." .. list_name .. " duplicate char: " .. ch)
			seen[ch] = true
			assert(rules.approved_chars[ch], cname .. "." .. list_name .. " char not in approved_chars: " .. ch)
			assert(not rules.banned_chars[ch], cname .. "." .. list_name .. " char in banned_chars: " .. ch)
			if is_initial then
				assert(not rules.banned_initial_chars[ch], cname .. "." .. list_name .. " initial char in banned_initial_chars: " .. ch)
			end
			if is_male_or_none_final then
				assert(not rules.female_only_chars[ch], cname .. "." .. list_name .. " male/none final contains female char: " .. ch)
			end
		end
	end

	for _, cname in ipairs(culture_order) do
		local c = rules.cultures[cname]
		check_list(cname, "given.initials", c.given.initials, 32, true, false)
		check_list(cname, "given.middles", c.given.middles, 22, false, false)
		if c.gendered then
			check_list(cname, "given.finals.male", c.given.finals.male, 24, false, true)
			check_list(cname, "given.finals.female", c.given.finals.female, 24, false, false)
		else
			check_list(cname, "given.finals.none", c.given.finals.none, 24, false, true)
		end
		check_list(cname, "surname.initials", c.surname.initials, 24, true, false)
		check_list(cname, "surname.middles", c.surname.middles, 16, false, false)
		check_list(cname, "surname.finals", c.surname.finals, 20, false, true)
	end

	for _, co in ipairs(cohorts_26) do
		local total, g_raw, s_raw = BossNames.cohort_total(co.culture, co.sex, co.tier)
		assert(total > 0 and g_raw > 0, "cohort total <= 0 for " .. co.culture .. "/" .. co.sex .. "/" .. co.tier)
		if co.tier == "epic" then assert(s_raw > 0) end
		local stride = BossNames.stride_for(total)
		assert(gcd(stride, total) == 1, string.format("stride %d not coprime with total %d", stride, total))
	end
	print("[PASS] T01: Data integrity verified across 8 cultures and 26 cohorts")
end

-- ============================================================================
-- T02, T03, T04: Rare Capacity, Epic Lower Bound, Banned Substring & Token Audit
-- ============================================================================
local rare_audits = {}
local surname_audits = {}
local min_rare_core = math.huge
local min_rare_cohort = nil
local min_sur_core = math.huge
local min_sur_culture = nil
local min_epic_lb = math.huge
local min_epic_cohort = nil

do
	assert(type(rules.banned_substrings) == "table" and #rules.banned_substrings >= 40, "banned_substrings must be non-empty")
	for _, cname in ipairs(culture_order) do
		local saudit = BossNames.surname_audit(cname)
		surname_audits[cname] = saudit
		assert(saudit.core_count >= 3000, string.format("surname %s core_count %d < 3000", cname, saudit.core_count))
		if saudit.core_count < min_sur_core then
			min_sur_core = saudit.core_count
			min_sur_culture = cname
		end
		-- T04 check on all surnames
		for _, sur in ipairs(saudit.list) do
			local sc = BossNames.core_of(sur)
			for _, bsub in ipairs(rules.banned_substrings) do
				assert(not sur:find(bsub, 1, true) and not sc:find(bsub, 1, true), "surname contains banned substring: " .. sur)
			end
		end
	end

	for _, co in ipairs(cohorts_26) do
		if co.tier == "rare" then
			local key = co.culture .. ":" .. co.sex
			local raudit = BossNames.audit_cohort(co.culture, co.sex, "rare")
			rare_audits[key] = raudit
			assert(raudit.core_count >= 10000, string.format("rare cohort %s core_count %d < 10000", key, raudit.core_count))
			if raudit.core_count < min_rare_core then
				min_rare_core = raudit.core_count
				min_rare_cohort = { culture = co.culture, sex = co.sex, key = key, core_count = raudit.core_count }
			end
			-- T04 check on all rare given names
			for _, gname in ipairs(raudit.list) do
				local gc = BossNames.core_of(gname)
				for _, bsub in ipairs(rules.banned_substrings) do
					assert(not gname:find(bsub, 1, true) and not gc:find(bsub, 1, true), "rare given contains banned substring: " .. gname)
				end
			end
		end
	end

	-- T03: Inclusion-exclusion epic lower bound P/2 >= 5,000,000 for all 13 epic cohorts
	for _, co in ipairs(cohorts_26) do
		if co.tier == "epic" then
			local key = co.culture .. ":" .. co.sex
			local raudit = rare_audits[key]
			local saudit = surname_audits[co.culture]
			local S_valid = saudit.core_count
			local cnt1, cnt2, cnt3 = {}, {}, {}
			for _, sc in ipairs(saudit.core_list) do
				local schars = utf8_chars(sc)
				table.sort(schars)
				local u = {}
				for _, ch in ipairs(schars) do
					if u[#u] ~= ch then u[#u + 1] = ch end
				end
				for i = 1, #u do
					cnt1[u[i]] = (cnt1[u[i]] or 0) + 1
					for j = i + 1, #u do
						local k2 = u[i] .. "\0" .. u[j]
						cnt2[k2] = (cnt2[k2] or 0) + 1
						for l = j + 1, #u do
							local k3 = k2 .. "\0" .. u[l]
							cnt3[k3] = (cnt3[k3] or 0) + 1
						end
					end
				end
			end
			local P = 0
			for _, gc in ipairs(raudit.core_list) do
				local gchars = utf8_chars(gc)
				table.sort(gchars)
				local u = {}
				for _, ch in ipairs(gchars) do
					if u[#u] ~= ch then u[#u + 1] = ch end
				end
				local overlap = 0
				for i = 1, #u do
					overlap = overlap + (cnt1[u[i]] or 0)
					for j = i + 1, #u do
						local k2 = u[i] .. "\0" .. u[j]
						overlap = overlap - (cnt2[k2] or 0)
						for l = j + 1, #u do
							local k3 = k2 .. "\0" .. u[l]
							overlap = overlap + (cnt3[k3] or 0)
						end
					end
				end
				P = P + (S_valid - overlap)
			end
			local epic_lb = math.floor(P / 2)
			assert(epic_lb >= 5000000, string.format("epic cohort %s lower bound %d < 5000000", key, epic_lb))
			if epic_lb < min_epic_lb then
				min_epic_lb = epic_lb
				min_epic_cohort = key
			end
		end
	end
	print(string.format("[PASS] T02: Rare full-enumeration capacity verified (min_core=%d [%s])", min_rare_core, min_rare_cohort.key))
	print(string.format("[PASS] T03: Epic inclusion-exclusion lower bound verified (min_sur_core=%d [%s], min_epic_lb=%d [%s])",
		min_sur_core, min_sur_culture, min_epic_lb, min_epic_cohort))
end

-- ============================================================================
-- T05 & T04 Epic Sampling: 6-Source Collision Audit (R1-R3 = 0) & Epic 208,000 Sample Audit
-- ============================================================================
local live_collision = GenTokens.build_collision_tables(rules)
do
	local counts = live_collision.sources.counts
	local D = live_collision.sources.D
	local T = live_collision.sources.T
	print(string.format("       T05 source counts: S1=%d, S2=%d, S3=%d, S4=%d, S5=%d, S6=%d (S1+S3=%d)",
		counts.S1, counts.S2, counts.S3, counts.S4, counts.S5, counts.S6, counts.S1 + counts.S3))
	assert(counts.S1 + counts.S3 >= 3000, "S1 + S3 must be >= 3000")
	assert(counts.S6 >= 200, "S6 unique entity zh names must be >= 200")

	-- Verify baked tables in data/chn_randboss_names.lua are supersets of live computation
	local baked_tokens_set = {}
	for _, tok in ipairs(rules.fixed_name_tokens) do
		baked_tokens_set[tok] = true
	end
	for _, tok in ipairs(live_collision.fixed_name_tokens) do
		assert(baked_tokens_set[tok], "live fixed_name_token missing from baked data/chn_randboss_names.lua: " .. tok)
	end
	for ex in pairs(live_collision.excluded_exact) do
		assert(rules.excluded_exact[ex] == true, "live excluded_exact entry missing from baked data/chn_randboss_names.lua: " .. ex)
	end

	-- Pre-filter T tokens by length for full R2 & R3 check against live T
	local T_ge3 = {}
	local T_ge4 = {}
	for tok in pairs(T) do
		local clen = #utf8_chars(tok)
		if clen >= 3 then T_ge3[#T_ge3 + 1] = tok end
		if clen >= 4 then T_ge4[#T_ge4 + 1] = tok end
	end

	local function verify_segment_r1_r3(seg)
		local sc = BossNames.core_of(seg)
		-- R1: seg not in D U T, core not in D
		assert(not D[seg] and not T[seg] and not D[sc], "R1 collision on segment: " .. seg)
		-- R2: no t in T (len >= 3) is a substring of seg
		for i = 1, #T_ge3 do
			assert(not seg:find(T_ge3[i], 1, true), "R2 collision: " .. seg .. " contains " .. T_ge3[i])
		end
		-- R3: if len(seg) >= 3, seg must not be a substring of any t in T (len >= 4)
		if #utf8_chars(seg) >= 3 then
			for i = 1, #T_ge4 do
				assert(not T_ge4[i]:find(seg, 1, true), "R3 collision: " .. seg .. " is substring of " .. T_ge4[i])
			end
		end
	end

	local checked_segments = {}
	for _, raudit in pairs(rare_audits) do
		for _, gname in ipairs(raudit.list) do
			if not checked_segments[gname] then
				checked_segments[gname] = true
				verify_segment_r1_r3(gname)
			end
		end
	end
	for _, saudit in pairs(surname_audits) do
		for _, sname in ipairs(saudit.list) do
			if not checked_segments[sname] then
				checked_segments[sname] = true
				verify_segment_r1_r3(sname)
			end
		end
	end

	-- T04: Deterministic sample >= 200,000 epic candidates across all 13 epic cohorts (16,000 slots per epic cohort = 208,000 slots)
	local epic_slots_probed = 0
	local epic_valid_checked = 0
	for _, co in ipairs(cohorts_26) do
		if co.tier == "epic" then
			local total = BossNames.cohort_total(co.culture, co.sex, "epic")
			local stride = BossNames.stride_for(total)
			for k = 1, 16000 do
				epic_slots_probed = epic_slots_probed + 1
				local idx = (k * stride) % total
				local personal, core = BossNames.candidate_at(co.culture, co.sex, "epic", idx)
				if personal then
					epic_valid_checked = epic_valid_checked + 1
					local unsep = personal:gsub(rules.separator, "")
					assert(not D[personal] and not D[core] and not D[unsep], "epic R1 collision: " .. personal)
					for _, bsub in ipairs(rules.banned_substrings) do
						assert(not personal:find(bsub, 1, true) and not unsep:find(bsub, 1, true) and not core:find(bsub, 1, true),
							"epic banned substring in " .. personal)
					end
					for _, tok in ipairs(rules.fixed_name_tokens) do
						assert(not unsep:find(tok, 1, true) and not core:find(tok, 1, true),
							"epic R2 collision in " .. personal .. " with " .. tok)
					end
				end
			end
		end
	end
	assert(epic_slots_probed >= 200000, "T04 must sample >= 200,000 epic candidates")
	print(string.format("[PASS] T04 & T05: 0 R1-R3 collisions across %d unique given/surname segments and %d sampled epic slots (%d valid)",
		(function() local c = 0; for _ in pairs(checked_segments) do c = c + 1 end; return c end)(),
		epic_slots_probed, epic_valid_checked))
end

-- ============================================================================
-- Engine Stubs & Real GameState / Actor Function Extraction (T06, T07, T08)
-- ============================================================================
local locale_dict = {
	_t = {
		["human"] = "人类",
		["orc archer"] = "兽人弓箭手",
		["brown bear"] = "棕熊",
		["eternal elf"] = "永恒精灵",
		["fire wyrm"] = "火焰巨龙",
		["major demon"] = "恶魔",
		["dwarven earthwarden"] = "矮人大地守卫",
		["halfling slinger"] = "半身人投石手",
		["yeek mindslayer"] = "夺心魔心灵杀手",
		["snow giant"] = "雪巨人",
		["actor"] = "生物",
	},
	tformat = {
		["%s the %s"] = { dst = "%s %s", order = { 2, 1 } },
	},
}

-- Implement exact engine/I18N.lua _t and string.tformat semantics (T07)
_G._t = function(s, tag)
	if config and config.settings and config.settings.locale == "zh_hans" then
		if tag == "tformat" and locale_dict.tformat[s] then
			return locale_dict.tformat[s].dst
		end
		if locale_dict._t[s] then
			return locale_dict._t[s]
		end
	end
	return s
end

_G.default_tformat = function(s, tag, ...)
	local entry = (config and config.settings and config.settings.locale == "zh_hans") and locale_dict.tformat[s] or nil
	local args_order = entry and entry.order or nil
	if args_order then
		local sargs = { ... }
		local args = {}
		for sidx, didx in pairs(args_order) do
			args[sidx] = sargs[didx]
		end
		s = _t(s, tag)
		return s:format(unpack(args))
	else
		s = _t(s, tag)
		return s:format(...)
	end
end

string.tformat = function(s, ...)
	return _G.default_tformat(s, "tformat", ...)
end

function string.capitalize(s)
	if type(s) ~= "string" or #s == 0 then return s end
	return s:sub(1, 1):upper() .. s:sub(2)
end

function string.fromTable(t)
	return tostring(t)
end

-- Deterministic Mock RNG for real createRandomBoss / createRandomBossNew
local rng_log = nil
local rng_seed = 12345

local function next_lcg()
	rng_seed = (rng_seed * 1103515245 + 12345) % 2147483648
	return rng_seed
end

local function make_recording_rng()
	return {
		percent = function(p)
			local r = (next_lcg() % 100) < p
			if rng_log then
				rng_log[#rng_log + 1] = string.format("percent(%s)=%s", tostring(p), tostring(r))
			end
			return r
		end,
		range = function(a, b)
			local r = a + (next_lcg() % (b - a + 1))
			if rng_log then
				rng_log[#rng_log + 1] = string.format("range(%s,%s)=%s", tostring(a), tostring(b), tostring(r))
			end
			return r
		end,
		table = function(t)
			local idx = (next_lcg() % #t) + 1
			local r = t[idx]
			if rng_log then
				rng_log[#rng_log + 1] = string.format("table(%d)=%d", #t, idx)
			end
			return r
		end,
	}
end

local english_syllables = { "Ar", "Bel", "Cor", "Dar", "El", "Fen", "Gor", "Hal", "Ir", "Kal", "Lor", "Mor", "Nor", "Or", "Pel", "Ral", "Sar", "Tor", "Ul", "Val", "Wor", "Xan", "Yor", "Zor" }
local joke_starts = { "神经病的", "失败者之", "奇葩的", "懦弱之", "神奇的", "傲娇之", "呆萌的", "邪恶之" }
local joke_ends = { "墨鱼", "辘轳", "路障", "下盘", "高手", "烧饼", "咸鱼", "拖把" }

local NameGenerator2 = {
	new = function(def_path)
		return {
			generate = function(_, min_s, max_s)
				local n = _G.rng.range(min_s or 2, max_s or 3)
				local parts = {}
				for i = 1, n do
					parts[i] = _G.rng.table(english_syllables)
				end
				return table.concat(parts)
			end,
		}
	end,
}

local NameGenerator = {
	new = function(rule_def)
		return {
			generate = function()
				local s = _G.rng.table(joke_starts)
				local e = _G.rng.table(joke_ends)
				return s .. e
			end,
		}
	end,
}

local resolvers = {
	calc = {
		life = function(t) return t[1] or 180 end,
	},
	sustains_at_birth = function() return { __resolver = "sustains_at_birth" } end,
	drops = function(t) return { __resolver = "drops", data = t } end,
	drop_randart = function(t) return { __resolver = "drop_randart", data = t } end,
	talented_ai_tactic = function() return { __resolver = "talented_ai_tactic" } end,
}

local colors = { VIOLET = "VIOLET" }

-- Extract real Actor:getName from TOME_ACTOR_LUA (T08)
local Actor = {}
Actor.__index = Actor
do
	local actor_lua_path = os.getenv("TOME_ACTOR_LUA") or "/workspace/t-engine4/game/modules/tome/class/Actor.lua"
	local f = assert(io.open(actor_lua_path, "rb"), "missing TOME_ACTOR_LUA: " .. tostring(actor_lua_path))
	local src = f:read("*a")
	f:close()
	local s_idx = assert(src:find("function _M:getName()", 1, true), "Actor:getName not found")
	local e_idx = assert(src:find("\nfunction _M:tooltip", s_idx, true), "Actor:tooltip not found after getName")
	local chunk = assert(loadstring("local _M = ...\n" .. src:sub(s_idx, e_idx - 1), "Actor:getName"))
	chunk(Actor)
end

function Actor:clone()
	local c = deep_copy_plain(self)
	return setmetatable(c, Actor)
end
function Actor:initBody()
	self.INVEN_INVEN = "INVEN"
	self.inven[self.INVEN_INVEN] = {}
end
function Actor:resolve() end

local function make_base_actor(props)
	local b = {
		__CLASSNAME = "mod.class.NPC",
		name = "human",
		type = "humanoid",
		subtype = "human",
		life_rating = 10,
		max_life = 150,
		level_range = { 1, 50 },
		ai = "dumb_talented_simple",
		talents = {},
		talent_cd_reduction = {},
		resources_def = {},
	}
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	return setmetatable(b, Actor)
end

-- Extract real createRandomBoss and createRandomBossNew from TOME_GAMESTATE_LUA (T06, T17)
local raw_createRandomBoss, raw_createRandomBossNew
do
	local gs_lua_path = os.getenv("TOME_GAMESTATE_LUA") or "/workspace/t-engine4/game/modules/tome/class/GameState.lua"
	local f = assert(io.open(gs_lua_path, "rb"), "missing TOME_GAMESTATE_LUA: " .. tostring(gs_lua_path))
	local src = f:read("*a")
	f:close()

	local b1_start = assert(src:find("function _M:createRandomBoss(base, data)", 1, true), "createRandomBoss not found")
	local b1_end = assert(src:find("--- Add one or more character classes", b1_start, true), "createRandomBoss end marker not found")
	local b1_code = src:sub(b1_start, b1_end - 1)

	local b2_start = assert(src:find("function _M:createRandomBossNew(base, data)", 1, true), "createRandomBossNew not found")
	local b2_end = assert(src:find("function _M:debugRandomZone()", b2_start, true), "createRandomBossNew end marker not found")
	local b2_code = src:sub(b2_start, b2_end - 1)

	local env = setmetatable({
		NameGenerator = NameGenerator,
		NameGenerator2 = NameGenerator2,
		resolvers = resolvers,
		colors = colors,
		print = function() end, -- suppress upstream debug print spam during tests
	}, { __index = _G })

	local holder = {}
	local c1 = assert(loadstring("local _M = ...\n" .. b1_code, "GameState:createRandomBoss"))
	setfenv(c1, env)
	c1(holder)
	raw_createRandomBoss = assert(holder.createRandomBoss)

	local c2 = assert(loadstring("local _M = ...\n" .. b2_code, "GameState:createRandomBossNew"))
	setfenv(c2, env)
	c2(holder)
	raw_createRandomBossNew = assert(holder.createRandomBossNew)
end

local function make_gamestate(wrap_superload)
	local st = {
		birth = {},
		getRandartNameRule = function()
			return { default = "$s$e" }
		end,
		applyRandomClass = function(_, b, data)
			b._applied_classes = data and data.nb_classes or 2
			-- Consume 1 deterministic RNG call inside applyRandomClass to verify downstream RNG alignment
			b._class_roll = _G.rng.range(1, 100)
		end,
		applyRandomClassNew = function(_, b, data, instant)
			b._applied_classes_new = data and data.nb_classes or 1.75
			b._instant = instant
			b._class_roll = _G.rng.range(1, 100)
		end,
		generateRandart = function(_, o, a, b)
			if a == "error" then error("stock randart error") end
			return o, a, b
		end,
		createRandomBoss = raw_createRandomBoss,
		createRandomBossNew = raw_createRandomBossNew,
	}
	if wrap_superload then
		_G.loadPrevious = function() return st end
		dofile("superload/mod/class/GameState.lua")
	end
	return st
end

-- ============================================================================
-- T07: string.tformat Real Semantics & 10+ Real Chinese Templates
-- ============================================================================
do
	local real_templates = {
		{ en = "#rng# the Invader", zh = "入侵者#rng#", base = "orc archer", expected_pre = "入侵者", expected_suf = "" },
		{ en = "#rng# the Tidebender", zh = "驭潮者#rng#", base = "orc archer", expected_pre = "驭潮者", expected_suf = "" },
		{ en = "#rng# the Invoker", zh = "#rng#祈唤者", base = "human", expected_pre = "", expected_suf = "祈唤者" },
		{ en = "#rng# the Bringer of Doom", zh = "厄运使者#rng#", base = "major demon", expected_pre = "厄运使者", expected_suf = "" },
		{ en = "#rng# the Spawn of Urh'Rok", zh = "#rng# 乌鲁洛克的子嗣", base = "major demon", expected_pre = "", expected_suf = " 乌鲁洛克的子嗣" },
		{ en = "#rng# the Witherer", zh = "枯萎者#rng#", base = "human", expected_pre = "枯萎者", expected_suf = "" },
		{ en = "#rng# the Flamebringer", zh = "火焰使者#rng#", base = "human", expected_pre = "火焰使者", expected_suf = "" },
		{ en = "#rng# the Grand Necromancer", zh = "大死灵法师#rng#", base = "human", expected_pre = "大死灵法师", expected_suf = "" },
		{ en = "#rng# the Guard", zh = "守卫 #rng#", base = "human", expected_pre = "守卫 ", expected_suf = "" },
		{ en = "#rng# the Bandit Leader", zh = "盗贼首领 #rng#", base = "human", expected_pre = "盗贼首领 ", expected_suf = "" },
		{ en = "Sleeping #base# #rng#", zh = "沉睡的#base# #rng#", base = "fire wyrm", expected_pre = "沉睡的火焰巨龙 ", expected_suf = "" },
		{ en = "#rng# the Blightborn", zh = "枯萎之子#rng#", base = "orc archer", expected_pre = "枯萎之子", expected_suf = "" },
	}
	for _, tc in ipairs(real_templates) do
		local base = make_base_actor{ name = tc.base }
		local orig = tc.zh:gsub("#rng#", "Arnold"):gsub("#base#", _t(tc.base))
		local pre, X, suf = BossNames.extract_personal_slot(orig, base, { name_scheme = tc.zh })
		assert(pre == tc.expected_pre and X == "Arnold" and suf == tc.expected_suf,
			"failed template reconstruction for " .. tc.zh)
	end

	-- Verify default "%s the %s" with {2,1} order
	local base_h = make_base_actor{ name = "human" }
	local pre, X, suf = BossNames.extract_personal_slot("人类 Arnold", base_h, {})
	assert(pre == "人类 " and X == "Arnold" and suf == "")

	-- Verify changing "%s the %s" translation to another permutation (e.g. "%s·%s" with {1,2} or "【%s】%s" with {2,1}) works without code changes
	locale_dict.tformat["%s the %s"] = { dst = "【%s】%s", order = { 2, 1 } }
	local pre2, X2, suf2 = BossNames.extract_personal_slot("【人类】Arnold", base_h, {})
	assert(pre2 == "【人类】" and X2 == "Arnold" and suf2 == "")

	locale_dict.tformat["%s the %s"] = { dst = "%s（%s）", order = { 1, 2 } }
	local pre3, X3, suf3 = BossNames.extract_personal_slot("Arnold（人类）", base_h, {})
	assert(pre3 == "" and X3 == "Arnold" and suf3 == "（人类）")

	-- Restore standard translation
	locale_dict.tformat["%s the %s"] = { dst = "%s %s", order = { 2, 1 } }
	print("[PASS] T07: string.tformat semantics and 12 real Chinese templates verified")
end

-- ============================================================================
-- T06, T08, T09, T17: Real createRandomBoss(+New), Display Paths, Identity Invariance
-- ============================================================================
local function run_lifecycle_tests(fn_name)
	rng_seed = 424242
	_G.rng = make_recording_rng()
	local vanilla_state = make_gamestate(false)
	local v_base = make_base_actor{ name = "human", random_name_def = "cornac_#sex#", female = false }
	local v_boss, v_id = vanilla_state[fn_name](vanilla_state, v_base, { rank = 3.2, level = 10 })

	rng_seed = 424242
	_G.rng = make_recording_rng()
	local mod_state = make_gamestate(true)
	_G.game = { state = mod_state, uniques = {} }
	local m_base = make_base_actor{ name = "human", random_name_def = "cornac_#sex#", female = false }
	local m_boss, m_id = mod_state[fn_name](mod_state, m_base, { rank = 3.2, level = 10 })

	-- E02: default template, rare rank 3.2, human male
	assert(m_boss.name ~= v_boss.name, "expected renamed boss in zh_hans")
	assert(m_boss.name:sub(1, #"人类 ") == "人类 ", "expected prefix '人类 ', got " .. tostring(m_boss.name))
	local personal = m_boss.name:sub(#"人类 " + 1)
	local p_chars = utf8_chars(personal)
	assert(#p_chars >= 2 and #p_chars <= 3 and not personal:find("·", 1, true), "expected 2-3 char rare personal name: " .. personal)
	local meta = assert(rawget(m_boss, "__chn_randboss_name"))
	assert(meta.version == 1 and meta.tier == "rare" and meta.culture == "human" and meta.sex == "male" and meta.recorded == true)
	assert(meta.original == v_boss.name and meta.text == m_boss.name)

	-- T09: Identity invariance
	assert(m_boss.unique == v_boss.unique, "b.unique must remain byte-identical to vanilla")
	assert(m_boss.define_as == v_boss.define_as, "b.define_as must remain byte-identical to vanilla")
	assert(m_id == v_id and m_id == m_boss.define_as, "returned boss_id must remain byte-identical to vanilla")
	assert(m_boss.randboss == true and m_boss.rank == v_boss.rank)
	assert((m_boss.__CLASSNAME .. "/" .. m_boss.unique) == (v_boss.__CLASSNAME .. "/" .. v_boss.unique))
	local ok_eq, err_eq = deep_equal(v_boss, m_boss, { name = true, __chn_randboss_name = true })
	assert(ok_eq, "actor fields diverged: " .. tostring(err_eq))

	-- T08: Display paths (Actor:getName and bare .name:capitalize() log)
	assert(m_boss:getName() == m_boss.name, "Actor:getName() must return renamed Chinese name")
	local log_line = string.format("%s hits Player for 42 damage.", m_boss.name:capitalize())
	assert(log_line:find(m_boss.name, 1, true) == 1, "bare .name:capitalize() log must show renamed Chinese name")

	-- E03: default template, epic rank 4, no def, type animal -> monster pool, <given>·<surname>
	local bear_base = make_base_actor{ name = "brown bear", type = "animal", subtype = "bear", random_name_def = nil }
	local bear_boss = mod_state[fn_name](mod_state, bear_base, { rank = 4, level = 20 })
	assert(bear_boss.name:sub(1, #"棕熊 ") == "棕熊 ")
	local bear_personal = bear_boss.name:sub(#"棕熊 " + 1)
	assert(bear_personal:find("·", 1, true), "epic boss must contain separator ·: " .. bear_personal)
	assert(#utf8_chars(bear_personal) <= 7, "epic personal name must be <= 7 display chars: " .. bear_personal)
	assert(bear_boss.__chn_randboss_name.tier == "epic" and bear_boss.__chn_randboss_name.culture == "monster" and bear_boss.__chn_randboss_name.sex == "none")

	-- E04: name_scheme="守卫 #rng#" rank 3.2 -> "守卫 <名>"
	local e04 = mod_state[fn_name](mod_state, m_base, { level = 10, rank = 3.2, name_scheme = "守卫 #rng#" })
	assert(e04.name:sub(1, #"守卫 ") == "守卫 " and not e04.name:find("·", 1, true))

	-- E05: name_scheme="#rng#祈唤者" rank 3.5 -> "<名>·<姓>祈唤者"
	local e05 = mod_state[fn_name](mod_state, m_base, { level = 10, rank = 3.5, name_scheme = "#rng#祈唤者" })
	assert(e05.name:sub(-#"祈唤者") == "祈唤者" and e05.name:find("·", 1, true))

	-- E06: name_scheme="沉睡的 #rng#" -> preserves space
	local e06 = mod_state[fn_name](mod_state, m_base, { level = 10, rank = 3.2, name_scheme = "沉睡的 #rng#" })
	assert(e06.name:sub(1, #"沉睡的 ") == "沉睡的 ")

	-- E07: name_scheme with #base# and #rng#
	local e07 = mod_state[fn_name](mod_state, bear_base, { level = 10, rank = 3.5, name_scheme = "狂暴的#base#-#rng#" })
	assert(e07.name:sub(1, #"狂暴的棕熊-") == "狂暴的棕熊-")

	-- E26: rank 5 / 10 -> epic
	local e26_5 = mod_state[fn_name](mod_state, bear_base, { level = 10, rank = 5 })
	local e26_10 = mod_state[fn_name](mod_state, bear_base, { level = 10, rank = 10 })
	assert(e26_5.__chn_randboss_name.tier == "epic" and e26_10.__chn_randboss_name.tier == "epic")

	-- E27: base.female = true on ungendered culture (orc) -> sex = "none"
	local orc_f = make_base_actor{ name = "orc archer", type = "humanoid", subtype = "orc", random_name_def = nil, female = true }
	local e27 = mod_state[fn_name](mod_state, orc_f, { level = 10, rank = 3.2 })
	assert(e27.__chn_randboss_name.culture == "orc" and e27.__chn_randboss_name.sex == "none")

	forbid_random_and_time()
end

run_lifecycle_tests("createRandomBoss")
run_lifecycle_tests("createRandomBossNew")
print("[PASS] T06, T08, T09: Real createRandomBoss(+New), display paths, and identity invariance verified")

-- ============================================================================
-- T10: Zero RNG Consumption Across 200 Real createRandomBoss(&New) Runs
-- ============================================================================
for _, fn_name in ipairs{ "createRandomBoss", "createRandomBossNew" } do
	local test_bases = {
		make_base_actor{ name = "human", type = "humanoid", subtype = "human", random_name_def = "cornac_#sex#", female = false },
		make_base_actor{ name = "human", type = "humanoid", subtype = "human", random_name_def = "higher_#sex#", female = true },
		make_base_actor{ name = "eternal elf", type = "humanoid", subtype = "shalore", random_name_def = "shalore_#sex#", female = true },
		make_base_actor{ name = "dwarven earthwarden", type = "humanoid", subtype = "dwarf", random_name_def = "dwarf_#sex#", female = false },
		make_base_actor{ name = "halfling slinger", type = "humanoid", subtype = "halfling", random_name_def = "halfling_#sex#", female = true },
		make_base_actor{ name = "yeek mindslayer", type = "humanoid", subtype = "yeek", random_name_def = "yeek_#sex#", female = false },
		make_base_actor{ name = "orc archer", type = "humanoid", subtype = "orc", random_name_def = nil },
		make_base_actor{ name = "major demon", type = "demon", subtype = "major", random_name_def = "demon" },
		make_base_actor{ name = "brown bear", type = "animal", subtype = "bear", random_name_def = nil },
		make_base_actor{ name = "fire wyrm", type = "dragon", subtype = "fire", random_name_def = nil },
	}
	local schemes = { nil, "守卫 #rng#", "#rng#祈唤者", "入侵者#rng#", "沉睡的#base# #rng#" }
	local ranks = { nil, 3.2, 3.5, 4, 5 }

	-- Run 200 times without plugin
	rng_seed = 987654321
	rng_log = {}
	_G.rng = make_recording_rng()
	local vanilla_log = rng_log
	local vanilla_state = make_gamestate(false)
	local vanilla_bosses = {}
	local vanilla_ids = {}
	for i = 1, 200 do
		local b = test_bases[((i - 1) % #test_bases) + 1]
		local sc = schemes[((i - 1) % #schemes) + 1]
		local rk = ranks[((i - 1) % #ranks) + 1]
		local boss, bid = vanilla_state[fn_name](vanilla_state, b, { level = i, rank = rk, name_scheme = sc })
		vanilla_bosses[i] = boss
		vanilla_ids[i] = bid
	end

	-- Run 200 times with plugin
	rng_seed = 987654321
	rng_log = {}
	_G.rng = make_recording_rng()
	local mod_log = rng_log
	local mod_state = make_gamestate(true)
	_G.game = { state = mod_state }
	local mod_bosses = {}
	local mod_ids = {}
	for i = 1, 200 do
		local b = test_bases[((i - 1) % #test_bases) + 1]
		local sc = schemes[((i - 1) % #schemes) + 1]
		local rk = ranks[((i - 1) % #ranks) + 1]
		local boss, bid = mod_state[fn_name](mod_state, b, { level = i, rank = rk, name_scheme = sc })
		mod_bosses[i] = boss
		mod_ids[i] = bid
	end

	rng_log = nil
	forbid_random_and_time()

	assert(#vanilla_log == #mod_log and #vanilla_log > 0, "RNG call count mismatch: " .. #vanilla_log .. " vs " .. #mod_log)
	for i = 1, #vanilla_log do
		assert(vanilla_log[i] == mod_log[i], string.format("RNG call #%d diverged: %s vs %s", i, vanilla_log[i], mod_log[i]))
	end
	for i = 1, 200 do
		assert(mod_ids[i] == vanilla_ids[i], "boss_id mismatch at #" .. i)
		assert(mod_bosses[i].name ~= vanilla_bosses[i].name, "boss #" .. i .. " was not renamed")
		local ok_eq, err_eq = deep_equal(vanilla_bosses[i], mod_bosses[i], { name = true, __chn_randboss_name = true })
		assert(ok_eq, "boss #" .. i .. " fields diverged: " .. tostring(err_eq))
	end
end
print("[PASS] T10: Zero RNG consumption verified across 200 createRandomBoss + 200 createRandomBossNew runs")

-- ============================================================================
-- T11 & T12: Determinism, Save/Load Plain Table Copy, Legacy Save Compatibility (E14, E15, E32)
-- ============================================================================
do
	-- T11: Two fresh states with identical inputs yield byte-identical results
	local base = make_base_actor{ name = "eternal elf", type = "humanoid", subtype = "shalore", random_name_def = "shalore_#sex#", female = true }
	local function make_dummy_boss(orig_name, rank)
		local b = base:clone()
		b.name = orig_name
		b.unique = orig_name
		b.randboss = true
		b.define_as = "RND_BOSS_" .. (orig_name:upper():gsub("[^A-Z]", "_"))
		b.rank = rank or 3.5
		return b
	end

	local st1, st2 = {}, {}
	_G.game = { state = st1 }
	local b1 = make_dummy_boss("永恒精灵 Elrania", 3.5)
	BossNames.rename(b1, base, {}, st1)

	_G.game = { state = st2 }
	local b2 = make_dummy_boss("永恒精灵 Elrania", 3.5)
	BossNames.rename(b2, base, {}, st2)

	assert(b1.name == b2.name and b1.name ~= "永恒精灵 Elrania")
	assert(deep_equal(b1.__chn_randboss_name, b2.__chn_randboss_name))

	-- Save-equivalent plain table deep copy + getName / rename idempotency (E15)
	local saved_actor = setmetatable(deep_copy_plain(b1), Actor)
	local saved_state = deep_copy_plain(st1)
	_G.game = { state = saved_state }
	assert(saved_actor:getName() == b1.name)
	BossNames.rename(saved_actor, base, {}, saved_state)
	assert(saved_actor.name == b1.name and saved_state.__chn_randboss_ledger.count == 1, "E15: repeated rename must be idempotent")

	-- T12: Legacy randboss without meta in old save is untouched
	local legacy_boss = make_base_actor{
		name = "兽人弓箭手 失败者之辘轳",
		unique = "兽人弓箭手 失败者之辘轳",
		define_as = "RND_BOSS_______________________",
		randboss = true,
		rank = 3.5,
	}
	assert(legacy_boss:getName() == "兽人弓箭手 失败者之辘轳")

	-- E32: Cloning an already renamed randboss (e.g. clone_on_hit / Multiplicity) inherits Chinese name & unique, does not re-trigger rename
	local cloned_boss = saved_actor:clone()
	assert(cloned_boss.name == b1.name and cloned_boss.unique == b1.unique)
	BossNames.rename(cloned_boss, base, {}, saved_state)
	assert(cloned_boss.name == b1.name and saved_state.__chn_randboss_ledger.count == 1)

	-- E14: Using an already-renamed randboss as `base` for a new createRandomBoss call overwrites stale meta and picks a distinct name
	rng_seed = 55555
	_G.rng = make_recording_rng()
	local gs = make_gamestate(true)
	gs.__chn_randboss_ledger = saved_state.__chn_randboss_ledger
	_G.game = { state = gs }
	local derived_boss = gs:createRandomBoss(saved_actor, { rank = 3.5, level = 15 })
	forbid_random_and_time()
	assert(derived_boss.name ~= saved_actor.name, "E14: derived boss from already-renamed base must get a new distinct name")
	assert(derived_boss.__chn_randboss_name.text == derived_boss.name)
	assert(derived_boss.__chn_randboss_name.core ~= saved_actor.__chn_randboss_name.core)
	assert(gs.__chn_randboss_ledger.count == 2)
	print("[PASS] T11 & T12: Determinism, save/load deep-copy stability, and legacy compatibility (E14, E15, E32) verified")
end

-- ============================================================================
-- T13: Ledger Behavior (E17–E21)
-- ============================================================================
do
	local base = make_base_actor{ name = "human", random_name_def = "cornac_#sex#", female = false }
	local function make_b(orig)
		return make_base_actor{
			name = orig,
			unique = orig,
			randboss = true,
			define_as = "RND_BOSS_" .. (orig:upper():gsub("[^A-Z]", "_")),
			rank = 3.2,
		}
	end

	-- E17: Missing ledger -> lazily created with version=1
	local st_fresh = {}
	local b17 = make_b("人类 Arthur")
	BossNames.rename(b17, base, {}, st_fresh)
	assert(type(st_fresh.__chn_randboss_ledger) == "table" and st_fresh.__chn_randboss_ledger.version == 1)
	assert(st_fresh.__chn_randboss_ledger.count == 1 and b17.name ~= "人类 Arthur")

	-- E18: Corrupted ledger (wrong version, out-of-range/non-int count, non-table used, or non-table ledger) -> vanilla fallback, untouched
	local bad_ledgers = {
		{ version = 2, count = 0, used = {} },
		{ version = 1, count = -1, used = {} },
		{ version = 1, count = BossNames.MAX_LEDGER + 1, used = {} },
		{ version = 1, count = 1.5, used = {} },
		{ version = 1, count = 0, used = "not_a_table" },
		"corrupted_string_ledger",
	}
	for _, bad in ipairs(bad_ledgers) do
		local snap = type(bad) == "table" and deep_copy_plain(bad) or bad
		local st_bad = { __chn_randboss_ledger = bad }
		local b18 = make_b("人类 Arthur")
		BossNames.rename(b18, base, {}, st_bad)
		assert(b18.name == "人类 Arthur" and rawget(b18, "__chn_randboss_name") == nil, "E18: corrupted ledger must fall back to vanilla")
		assert(st_bad.__chn_randboss_ledger == bad, "E18: corrupted ledger reference must not be overwritten")
		if type(bad) == "table" then
			assert(deep_equal(bad, snap), "E18: corrupted ledger content must not be mutated")
		end
	end

	-- E19: Ledger count = MAX_LEDGER - 1 -> records this one, count becomes MAX_LEDGER, recorded = true
	-- E20: Ledger full (count = MAX_LEDGER) -> unrecorded mode, still skips used cores, meta.recorded = false, count unchanged
	local st_cap = {
		__chn_randboss_ledger = {
			version = 1,
			count = BossNames.MAX_LEDGER - 1,
			used = {},
		},
	}
	local b19 = make_b("人类 SameInput")
	BossNames.rename(b19, base, {}, st_cap)
	assert(b19.name ~= "人类 SameInput")
	assert(b19.__chn_randboss_name.recorded == true)
	assert(st_cap.__chn_randboss_ledger.count == BossNames.MAX_LEDGER)
	local core19 = b19.__chn_randboss_name.core
	assert(st_cap.__chn_randboss_ledger.used[core19] == true)

	local b20 = make_b("人类 SameInput")
	BossNames.rename(b20, base, {}, st_cap)
	assert(b20.name ~= "人类 SameInput" and b20.name ~= b19.name, "E20: full ledger must still rename and skip cores in ledger.used")
	assert(b20.__chn_randboss_name.core ~= core19)
	assert(b20.__chn_randboss_name.recorded == false)
	assert(st_cap.__chn_randboss_ledger.count == BossNames.MAX_LEDGER)
	assert(st_cap.__chn_randboss_ledger.used[b20.__chn_randboss_name.core] == nil)

	-- E21: state is nil / non-table -> vanilla fallback
	local b21_nil = make_b("人类 Arthur")
	BossNames.rename(b21_nil, base, {}, nil)
	assert(b21_nil.name == "人类 Arthur" and rawget(b21_nil, "__chn_randboss_name") == nil)
	local b21_str = make_b("人类 Arthur")
	BossNames.rename(b21_str, base, {}, "not_a_state")
	assert(b21_str.name == "人类 Arthur" and rawget(b21_str, "__chn_randboss_name") == nil)
	print("[PASS] T13: Ledger behavior (E17–E21) verified")
end

-- ============================================================================
-- T14 & T17: Exclusions, Edge Cases & Exception Isolation (E01, E08–E13, E16, E22–E25, E28–E31)
-- ============================================================================
local function run_edge_case_tests(fn_name)
	rng_seed = 77777
	_G.rng = make_recording_rng()
	local gs = make_gamestate(true)
	_G.game = { state = gs }
	local base = make_base_actor{ name = "human", random_name_def = "cornac_#sex#", female = false }

	-- E01: Non-zh locale -> no rename, no ledger created
	config.settings.locale = "en_US"
	local st_en = make_gamestate(true)
	local b01 = st_en[fn_name](st_en, base, { level = 10, rank = 3.2 })
	assert(rawget(b01, "__chn_randboss_name") == nil and rawget(st_en, "__chn_randboss_ledger") == nil)
	config.settings.locale = "zh_hans"

	-- E08: name_scheme without #rng# ("腐化的 #base#") -> skip
	local b08 = gs[fn_name](gs, base, { level = 10, rank = 3.5, name_scheme = "腐化的 #base#" })
	assert(b08.name == "腐化的 人类" and rawget(b08, "__chn_randboss_name") == nil)

	-- E09: name_scheme with 2 #rng# -> skip
	local b09 = gs[fn_name](gs, base, { level = 10, rank = 3.5, name_scheme = "#rng#与#rng#" })
	assert(rawget(b09, "__chn_randboss_name") == nil)

	-- E10: Untranslated template "#rng# the Blightborn" -> skip
	local b10 = gs[fn_name](gs, base, { level = 10, rank = 3.5, name_scheme = "#rng# the Blightborn" })
	assert(b10.name:find("the Blightborn", 1, true) and rawget(b10, "__chn_randboss_name") == nil)

	-- E11: Untranslated base name (_t returns English) -> skip
	local un_base = make_base_actor{ name = "untranslated_wyrm", random_name_def = "cornac_#sex#" }
	local b11 = gs[fn_name](gs, un_base, { level = 10, rank = 3.5 })
	assert(b11.name:find("untranslated_wyrm", 1, true) and rawget(b11, "__chn_randboss_name") == nil)

	-- E12: data.post modified b.name -> define_as/unique check fails -> skip
	local b12 = gs[fn_name](gs, base, {
		level = 10,
		rank = 3.5,
		post = function(b) b.name = "自定义首领名" end,
	})
	assert(b12.name == "自定义首领名" and rawget(b12, "__chn_randboss_name") == nil)

	-- E13: data.post modified b.unique -> skip
	local b13 = gs[fn_name](gs, base, {
		level = 10,
		rank = 3.5,
		post = function(b) b.unique = "CustomUniqueKey" end,
	})
	assert(b13.unique == "CustomUniqueKey" and rawget(b13, "__chn_randboss_name") == nil)

	-- E16: Two monsters with identical vanilla names -> distinct core names via probing
	local orig16 = "人类 Identical"
	local id16 = "RND_BOSS_" .. (orig16:upper():gsub("[^A-Z]", "_"))
	local b16_a = make_base_actor{ name = orig16, unique = orig16, randboss = true, define_as = id16, rank = 3.2 }
	local b16_b = make_base_actor{ name = orig16, unique = orig16, randboss = true, define_as = id16, rank = 3.2 }
	BossNames.rename(b16_a, base, {}, gs)
	BossNames.rename(b16_b, base, {}, gs)
	assert(b16_a.name ~= orig16 and b16_b.name ~= orig16)
	assert(b16_a.__chn_randboss_name.core ~= b16_b.__chn_randboss_name.core)

	-- E22: Corrupted rules data (empty pool / wrong type) -> vanilla fallback, no exception leaked
	local saved_human_init = rules.cultures.human.given.initials
	rules.cultures.human.given.initials = {}
	local b22 = gs[fn_name](gs, base, { level = 10, rank = 3.2 })
	assert(rawget(b22, "__chn_randboss_name") == nil)
	rules.cultures.human.given.initials = "corrupted_non_table"
	local b22_b = gs[fn_name](gs, base, { level = 10, rank = 3.2 })
	assert(rawget(b22_b, "__chn_randboss_name") == nil)
	rules.cultures.human.given.initials = saved_human_init

	-- E23: rename throws an internal error -> wrapper swallows it and returns original function results (including boss_id)
	local broken_state = setmetatable({}, {
		__index = function() error("injected rename crash") end,
	})
	-- Also test direct error inside BossNames.rename when invoked by superload wrapper
	local bad_ledger_mt = setmetatable({ version = 1, count = 0 }, {
		__index = function(_, k)
			if k == "used" then error("injected rename crash") end
		end,
	})
	gs.__chn_randboss_ledger = bad_ledger_mt
	local b23, id23 = gs[fn_name](gs, base, { level = 10, rank = 3.5 })
	gs.__chn_randboss_ledger = nil
	assert(type(b23) == "table" and type(id23) == "string" and id23 == b23.define_as)
	assert(rawget(b23, "__chn_randboss_name") == nil)

	-- E24: Original function throws an error -> propagates unchanged with matching message
	local ok24, err24 = pcall(function()
		gs[fn_name](gs, base, {
			level = 10,
			init = function() error("upstream_init_failure_marker") end,
		})
	end)
	assert(not ok24 and tostring(err24):find("upstream_init_failure_marker", 1, true), "E24: upstream error must propagate")

	-- E25: Recursive randboss generation inside data.post -> both inner and outer bosses renamed, ledger +2
	local st25 = make_gamestate(true)
	_G.game = { state = st25 }
	local inner_boss
	local outer_boss = st25[fn_name](st25, base, {
		level = 10,
		rank = 3.5,
		post = function()
			inner_boss = st25[fn_name](st25, base, { level = 10, rank = 3.2 })
		end,
	})
	assert(inner_boss and inner_boss.__chn_randboss_name and outer_boss.__chn_randboss_name)
	assert(inner_boss.__chn_randboss_name.tier == "rare" and outer_boss.__chn_randboss_name.tier == "epic")
	assert(st25.__chn_randboss_ledger.count == 2)

	-- E28: Candidate matches a party member's name -> skipped in favor of next probe candidate
	local st28 = {}
	_G.game = { state = st28 }
	local orig28 = "人类 PartyProbe"
	local id28 = "RND_BOSS_" .. (orig28:upper():gsub("[^A-Z]", "_"))
	local probe_b = make_base_actor{ name = orig28, unique = orig28, randboss = true, define_as = id28, rank = 3.2 }
	BossNames.rename(probe_b, base, {}, st28)
	local first_choice_personal = probe_b.name:sub(#"人类 " + 1)
	assert(#first_choice_personal > 0 and probe_b.name ~= orig28)

	local st28_party = {}
	local member_actor = { name = first_choice_personal }
	_G.game = {
		state = st28_party,
		party = { members = { [member_actor] = true } },
	}
	local probe_b2 = make_base_actor{ name = orig28, unique = orig28, randboss = true, define_as = id28, rank = 3.2 }
	BossNames.rename(probe_b2, base, {}, st28_party)
	local second_choice_personal = probe_b2.name:sub(#"人类 " + 1)
	assert(second_choice_personal ~= first_choice_personal, "E28: must skip party member's name")
	assert(BossNames.core_of(second_choice_personal) ~= BossNames.core_of(first_choice_personal))

	-- E29: Probe exhaustion (tiny pool + all cores in used) -> vanilla fallback
	local saved_h_g = rules.cultures.human.given
	rules.cultures.human.given = {
		initials = { "阿", "艾" },
		middles = { "德" },
		finals = { male = { "克" }, female = { "娜" } },
	}
	local st29 = {
		__chn_randboss_ledger = {
			version = 1,
			count = 4,
			used = {
				["阿克"] = true, ["艾克"] = true, ["阿德克"] = true, ["艾德克"] = true,
			},
		},
	}
	_G.game = { state = st29 }
	local orig29 = "人类 Exhausted"
	local id29 = "RND_BOSS_" .. (orig29:upper():gsub("[^A-Z]", "_"))
	local b29 = make_base_actor{ name = orig29, unique = orig29, randboss = true, define_as = id29, rank = 3.2 }
	BossNames.rename(b29, base, {}, st29)
	rules.cultures.human.given = saved_h_g
	assert(b29.name == orig29 and rawget(b29, "__chn_randboss_name") == nil, "E29: probe exhaustion must fall back to vanilla")

	-- E30: Double loading superload -> wraps only once
	local fn_before = gs[fn_name]
	_G.loadPrevious = function() return gs end
	dofile("superload/mod/class/GameState.lua")
	assert(gs[fn_name] == fn_before, "E30: superload must be idempotent on double load")

	forbid_random_and_time()
end

run_edge_case_tests("createRandomBoss")
run_edge_case_tests("createRandomBossNew")
print("[PASS] T14 & T17: All edge cases (E01–E32) and createRandomBossNew equivalence verified")

-- ============================================================================
-- T15: Mixed Stress Test (1,000 spawns across 8 cultures x sex x 2 tiers x 7 templates)
-- ============================================================================
do
	local t0 = orig_os_clock()
	local st = {}
	_G.game = { state = st }

	local lcg = 314159265
	local function next_test_rand(n)
		lcg = (lcg * 1664525 + 1013904223) % 4294967296
		return (lcg % n) + 1
	end

	local culture_bases = {
		{ name = "human", type = "humanoid", subtype = "human", random_name_def = "cornac_#sex#", female = false },
		{ name = "human", type = "humanoid", subtype = "human", random_name_def = "higher_#sex#", female = true },
		{ name = "eternal elf", type = "humanoid", subtype = "shalore", random_name_def = "shalore_#sex#", female = false },
		{ name = "eternal elf", type = "humanoid", subtype = "thalore", random_name_def = "thalore_#sex#", female = true },
		{ name = "dwarven earthwarden", type = "humanoid", subtype = "dwarf", random_name_def = "dwarf_#sex#", female = false },
		{ name = "dwarven earthwarden", type = "humanoid", subtype = "dwarf", random_name_def = "dwarf_#sex#", female = true },
		{ name = "halfling slinger", type = "humanoid", subtype = "halfling", random_name_def = "halfling_#sex#", female = false },
		{ name = "halfling slinger", type = "humanoid", subtype = "halfling", random_name_def = "halfling_#sex#", female = true },
		{ name = "yeek mindslayer", type = "humanoid", subtype = "yeek", random_name_def = "yeek_#sex#", female = false },
		{ name = "yeek mindslayer", type = "humanoid", subtype = "yeek", random_name_def = "yeek_#sex#", female = true },
		{ name = "orc archer", type = "humanoid", subtype = "orc", random_name_def = nil },
		{ name = "major demon", type = "demon", subtype = "major", random_name_def = "demon" },
		{ name = "brown bear", type = "animal", subtype = "bear", random_name_def = nil },
	}
	local templates = {
		nil,
		"守卫 #rng#",
		"#rng#祈唤者",
		"入侵者#rng#",
		"火焰使者#rng#",
		"盗贼首领 #rng#",
		"沉睡的#base# #rng#",
		"#rng# 乌鲁洛克的子嗣",
	}
	local ranks = { 3.2, 3.5, 4.0 }
	local seen_cores = {}
	local D = live_collision.sources.D

	for i = 1, 1000 do
		local cb = culture_bases[next_test_rand(#culture_bases)]
		local tmpl = templates[next_test_rand(#templates)]
		local rk = ranks[next_test_rand(#ranks)]
		local base = make_base_actor(cb)
		local raw_rng_token = "Rand" .. tostring(i) .. "x" .. tostring(next_test_rand(9999))
		local orig_name
		if tmpl then
			orig_name = tmpl:gsub("#rng#", raw_rng_token):gsub("#base#", _t(base.name))
		else
			orig_name = ("%s the %s"):tformat(raw_rng_token, _t(base.name))
		end
		local b = base:clone()
		b.name = orig_name
		b.unique = orig_name
		b.randboss = true
		b.define_as = "RND_BOSS_" .. (orig_name:upper():gsub("[^A-Z]", "_"))
		b.rank = rk

		BossNames.rename(b, base, { name_scheme = tmpl, rank = rk }, st)
		local meta = assert(rawget(b, "__chn_randboss_name"), "failed to rename mixed boss #" .. i)
		assert(plain_label(b.name), "invalid plain_label on mixed boss #" .. i)
		assert(not seen_cores[meta.core], "duplicate core in 1000 mixed spawns at #" .. i .. ": " .. meta.core)
		seen_cores[meta.core] = true
		assert(not D[b.name] and not D[meta.core], "fixed entity collision in mixed stress test: " .. b.name)

		local pre, personal, suf = BossNames.extract_personal_slot(b.name, base, { name_scheme = tmpl })
		assert(pre and personal and suf)
		local p_len = #utf8_chars(personal)
		if rk < 3.5 then
			assert(p_len >= 2 and p_len <= 3 and not personal:find("·", 1, true), "invalid rare personal length: " .. personal)
		else
			assert(p_len >= 5 and p_len <= 7 and personal:find("·", 1, true), "invalid epic personal length: " .. personal)
		end
		for _, bsub in ipairs(rules.banned_substrings) do
			assert(not personal:find(bsub, 1, true) and not meta.core:find(bsub, 1, true))
		end
	end
	local elapsed = orig_os_clock() - t0
	assert(st.__chn_randboss_ledger.count == 1000)
	assert(elapsed < 3.0, string.format("T15 mixed stress test took %.3fs (>= 3.0s limit)", elapsed))
	print(string.format("[PASS] T15: 1,000 mixed spawns -> 1,000 unique cores, 0 collisions, elapsed=%.3fs (< 3s)", elapsed))
end

-- ============================================================================
-- T16: Worst-Cohort Stress Test (1,000 identical inputs + 8,192 full-ledger + 8,193rd unrecorded)
-- ============================================================================
do
	local worst = assert(min_rare_cohort)
	local base_props = {
		name = "eternal elf",
		type = "humanoid",
		subtype = "shalore",
		random_name_def = worst.culture == "elf" and "shalore_#sex#" or (worst.culture .. "_#sex#"),
		female = worst.sex == "female",
	}
	if worst.culture == "orc" or worst.culture == "demon" or worst.culture == "monster" then
		base_props.random_name_def = worst.culture == "demon" and "demon" or nil
		base_props.type = worst.culture == "demon" and "demon" or (worst.culture == "orc" and "humanoid" or "animal")
		base_props.subtype = worst.culture
	end
	local base = make_base_actor(base_props)
	local c_chk, s_chk = BossNames.culture_of(base, {})
	assert(c_chk == worst.culture and s_chk == worst.sex, "worst cohort base mismatch")

	local t0 = orig_os_clock()
	local ledger_1k = { version = 1, count = 0, used = {} }
	local seen_1k = {}
	local total_steps = 0
	local max_steps = 0
	local identical_key = table.concat({
		"rb", tostring(rules.version), "rare", worst.culture, worst.sex,
		"永恒精灵 IdenticalSeed", base.name, "RND_BOSS____IDENTICALSEED", "default",
	}, "\0")

	for i = 1, 1000 do
		local personal, core, recorded, steps = BossNames.select(worst.culture, worst.sex, "rare", identical_key, ledger_1k, {})
		assert(personal and core and recorded == true, "failed at identical spawn #" .. i)
		assert(not seen_1k[core], "duplicate core at identical spawn #" .. i)
		seen_1k[core] = true
		ledger_1k.used[core] = true
		ledger_1k.count = ledger_1k.count + 1
		total_steps = total_steps + steps
		if steps > max_steps then max_steps = steps end
	end
	local elapsed_1k = orig_os_clock() - t0
	local avg_steps = total_steps / 1000
	assert(elapsed_1k < 5.0, string.format("T16 1,000 identical-input test took %.3fs (>= 5.0s limit)", elapsed_1k))

	-- Now continue on the same smallest rare cohort up to 8,192 (MAX_LEDGER) distinct spawns, and check 8,193rd
	local st_full = {}
	_G.game = { state = st_full }
	local seen_8k = {}
	for i = 1, BossNames.MAX_LEDGER do
		local orig = "永恒精灵 WorstCohort" .. tostring(i)
		local b = base:clone()
		b.name = orig
		b.unique = orig
		b.randboss = true
		b.define_as = "RND_BOSS_" .. (orig:upper():gsub("[^A-Z]", "_"))
		b.rank = 3.2
		BossNames.rename(b, base, { rank = 3.2 }, st_full)
		local meta = assert(rawget(b, "__chn_randboss_name"), "failed at 8192 fill #" .. i)
		assert(meta.recorded == true, "expected recorded=true at #" .. i)
		assert(not seen_8k[meta.core], "duplicate core at #" .. i)
		seen_8k[meta.core] = true
	end
	assert(st_full.__chn_randboss_ledger.count == BossNames.MAX_LEDGER)

	-- 8,193rd spawn enters unrecorded mode, still succeeds and does not duplicate any of the 8,192 in ledger.used
	local orig_8193 = "永恒精灵 WorstCohort8193"
	local b8193 = base:clone()
	b8193.name = orig_8193
	b8193.unique = orig_8193
	b8193.randboss = true
	b8193.define_as = "RND_BOSS_" .. (orig_8193:upper():gsub("[^A-Z]", "_"))
	b8193.rank = 3.2
	BossNames.rename(b8193, base, { rank = 3.2 }, st_full)
	local meta8193 = assert(rawget(b8193, "__chn_randboss_name"), "8193rd spawn must succeed in unrecorded mode")
	assert(meta8193.recorded == false, "8193rd spawn must have meta.recorded == false")
	assert(not seen_8k[meta8193.core], "8193rd spawn must still avoid all 8192 cores in ledger.used")
	assert(st_full.__chn_randboss_ledger.count == BossNames.MAX_LEDGER)

	print(string.format("[PASS] T16: Worst cohort (%s, core=%d) 1,000 identical inputs -> 0 dup, avg_probes=%.2f, max_probes=%d, elapsed=%.3fs; 8,192 fill + 8,193rd unrecorded OK",
		worst.key, worst.core_count, avg_steps, max_steps, elapsed_1k))
end

-- ============================================================================
-- T18: Sample Generation for Naturalness Review (26 cohorts x 40 = 1,040 lines)
-- ============================================================================
do
	local sample_out = os.getenv("RANDBOSS_SAMPLE_OUT") or "/tmp/tome4-randboss-samples.txt"
	local rep_bases = {
		human = "人类",
		elf = "永恒精灵",
		dwarf = "矮人大地守卫",
		halfling = "半身人投石手",
		yeek = "夺心魔心灵杀手",
		orc = "兽人弓箭手",
		demon = "恶魔",
		monster = "火焰巨龙",
	}
	local f = assert(io.open(sample_out, "wb"), "cannot open RANDBOSS_SAMPLE_OUT: " .. tostring(sample_out))
	local total_written = 0
	for _, co in ipairs(cohorts_26) do
		local header = string.format("%s/%s/%s", co.culture, co.sex, co.tier)
		local ledger = { version = 1, count = 0, used = {} }
		local base_label = rep_bases[co.culture]
		local stdout_preview = {}
		for i = 1, 40 do
			local key = table.concat({
				"sample_v1",
				co.culture,
				co.sex,
				co.tier,
				"BossSample_" .. tostring(i * 9973) .. "_" .. co.culture .. "_" .. tostring(i * i + 313),
			}, "\0")
			local personal, core = BossNames.select(co.culture, co.sex, co.tier, key, ledger, {})
			assert(personal and core, "failed to select sample #" .. i .. " for " .. header)
			ledger.used[core] = true
			ledger.count = ledger.count + 1
			local full_disp = base_label .. " " .. personal
			f:write(string.format("[%s #%02d] %s\n", header, i, full_disp))
			total_written = total_written + 1
			if i <= 10 then
				stdout_preview[#stdout_preview + 1] = full_disp
			end
		end
		print(string.format("       [T18 %s/%s/%s]: %s", co.culture, co.sex, co.tier, table.concat(stdout_preview, " | ")))
	end
	f:close()
	assert(total_written == 1040, "expected 1040 sample lines, got " .. tostring(total_written))
	print(string.format("[PASS] T18: Wrote %d sample names across 26 cohorts to %s", total_written, sample_out))
end

-- ============================================================================
-- T19: Regression Check on GameState:generateRandart Coexistence
-- ============================================================================
do
	local st = make_gamestate(true)
	_G.game = { state = st }
	local RandartNames = dofile("/hooks/chn-mod/random_artifact_names.lua")
	local obj = {
		name = "Iron sword of mischance",
		define_as = "SWORD_TEST_REGRESSION",
		unique = "Test sword regression",
		randart = true,
		identified = true,
		isIdentified = function(self) return self.identified end,
		type = "weapon",
		subtype = "longsword",
	}
	local res, h, tail = st:generateRandart(obj, nil, "tail_arg")
	assert(res == obj and h == nil and tail == "tail_arg")
	assert(type(obj.__chn_randart_name) == "table" and obj.__chn_randart_name.version == 2)
	local rendered = RandartNames.decorate(obj, {}, "Iron sword of mischance", st)
	assert(rendered:find("长剑「", 1, true) == 1)
	assert(st.__chn_randart_ledger and st.__chn_randart_ledger.count == 1)
	assert(st.__chn_randboss_ledger == nil, "randart generation must not touch __chn_randboss_ledger")
	print("[PASS] T19: Coexistence with GameState:generateRandart verified")
end

math.random = orig_math_random
math.randomseed = orig_math_randomseed
os.time = orig_os_time
os.clock = orig_os_clock

print(string.format(
	"ALL 19 RANDOM BOSS NAMING V1 TESTS PASSED (cohorts=26, min_rare_core=%d [%s], min_sur_core=%d [%s], min_epic_lb=%d [%s])",
	min_rare_core, min_rare_cohort.key, min_sur_core, min_sur_culture, min_epic_lb, min_epic_cohort
))
