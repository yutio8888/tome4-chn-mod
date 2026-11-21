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

	local function check_list(cname, list_name, lst, min_len, is_initial, reject_female_chars)
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
			if reject_female_chars then
				assert(not rules.female_only_chars[ch], cname .. "." .. list_name .. " non-female pool contains female_only_chars: " .. ch)
			end
		end
	end

	for _, cname in ipairs(culture_order) do
		local c = rules.cultures[cname]
		-- Strict §4.6.7 compliance across all positions of male/neutral given pools and shared surname pools
		check_list(cname, "given.initials", c.given.initials, 32, true, true)
		check_list(cname, "given.middles", c.given.middles, 22, false, true)
		if c.gendered then
			check_list(cname, "given.finals.male", c.given.finals.male, 24, false, true)
			check_list(cname, "given.finals.female", c.given.finals.female, 24, false, false)
		else
			check_list(cname, "given.finals.none", c.given.finals.none, 24, false, true)
		end
		check_list(cname, "surname.initials", c.surname.initials, 24, true, true)
		check_list(cname, "surname.middles", c.surname.middles, 16, false, true)
		check_list(cname, "surname.finals", c.surname.finals, 20, false, true)
	end

	for _, co in ipairs(cohorts_26) do
		local total, g_raw, s_raw = BossNames.cohort_total(co.culture, co.sex, co.tier)
		assert(total > 0 and g_raw > 0, "cohort total <= 0 for " .. co.culture .. "/" .. co.sex .. "/" .. co.tier)
		if co.tier == "epic" then assert(s_raw > 0) end
		local stride = BossNames.stride_for(total)
		assert(gcd(stride, total) == 1, string.format("stride %d not coprime with total %d", stride, total))
	end
	print("[PASS] T01: Data integrity verified across 8 cultures and 26 cohorts (strict §4.6.7 gender char compliance)")
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
-- T05 & T04 Epic Sampling: 6-Source Collision Audit (R1-R3 = 0) & Epic 208,000 Valid Sample Audit
-- ============================================================================
local live_collision = GenTokens.build_collision_tables(rules)
do
	local counts = live_collision.sources.counts
	local D = live_collision.sources.D
	local T = live_collision.sources.T
	print(string.format("       T05 source counts: S1=%d, S2=%d, S3=%d, S4=%d, S5=%d, S6=%d (defs=%d, en=%d, S1+S3=%d)",
		counts.S1, counts.S2, counts.S3, counts.S4, counts.S5, counts.S6, counts.S6_defs, counts.S6_en, counts.S1 + counts.S3))
	assert(counts.S1 + counts.S3 >= 3000, "S1 + S3 must be >= 3000")
	assert(counts.S6 >= 200, "S6 unique entity zh names must be >= 200")
	assert(counts.S6_core_defs > 0 and counts.S6_dlc_defs > 0, "S6 must find definitions in both core and DLCs")

	-- B4 verification: all-context translations included, unided_name excluded, missing/duplicate sources rejected
	assert(D["炎华月"] and D["霜华月"] and D["种族灭绝"], "S6 must include all translation contexts from S1-S4")
	assert(not D["光辉的精灵木长弓"], "S6 must not extract unided_name as entity name")
	assert(D["部落高阶大地法师沃尔"] and rules.excluded_exact["部落高阶大地法师沃尔"] == true, "Vor full Chinese name must be in D and baked excluded_exact")

	-- Negative tests for B4 source validation:
	-- 1) Missing core tome_data_dir must fail
	local ok_missing_core = pcall(GenTokens.collect_sources, { tome_data_dir = "/nonexistent_tome_data_dir_12345" })
	assert(not ok_missing_core, "collect_sources must fail when tome_data_dir does not exist")
	-- 2) Missing DLC root must fail
	local ok_missing_dlc = pcall(GenTokens.collect_sources, { dlc_root = "/nonexistent_dlc_root_12345" })
	assert(not ok_missing_dlc, "collect_sources must fail when dlc_root does not exist")
	-- 3) Duplicate DLC locale files must fail
	local cults_zh = (os.getenv("DLC_ROOT") or "/workspace/tome4-dlcs") .. "/cults/tome-cults/data/locales/zh_hans.lua"
	local ok_dup_dlc = pcall(GenTokens.collect_sources, { dlc_paths = { cults_zh, cults_zh, cults_zh } })
	assert(not ok_dup_dlc, "collect_sources must fail when duplicate DLC locale files are provided")
	-- 4) Lexical S6 parser must ignore comments, nested tables, non-literal unique, and unided_name
	local synthetic_lua = [=[
		-- newEntity{ name = "CommentedEntity", unique = true }
		--[[ newEntity{ name = "BlockCommentEntity", unique = true } ]]
		newEntity{
			base = "BASE_BOW",
			name = "RealUniqueBow",
			unided_name = _t"shining elven-wood longbow",
			unique = true,
			nested = { name = "NestedFakeName", unique = true },
		}
		newEntity{
			name = "NonUniqueEntity",
			unique = false,
		}
		newEntity{
			unique = true and false,
			name = "BooleanExpression",
		}
		newEntity{
			unique = true,
			name = "Top",
			act = function()
				do local x = 1; name = "Assignment"; end
			end,
		}
	]=]
	local extracted_syn = GenTokens.extract_fixed_entities_from_source(synthetic_lua)
	assert(#extracted_syn == 2 and extracted_syn[1] == "RealUniqueBow" and extracted_syn[2] == "Top",
		"S6 lexical extractor failed synthetic boundary check: got " .. table.concat(extracted_syn, ","))

	-- B4 negative check 3: physical directory aliasing (tome_data_dir and dlc_root pointing to same physical directory via "/.")
	local real_tome_data = os.getenv("TOME_DATA_DIR") or "/workspace/t-engine4/game/modules/tome/data"
	local real_dlc_root = os.getenv("DLC_ROOT") or "/workspace/tome4-dlcs"
	local dlc_a = real_dlc_root .. "/ashes-urhrok/tome-ashes-urhrok/data/locales/zh_hans.lua"
	local dlc_c = real_dlc_root .. "/cults/tome-cults/data/locales/zh_hans.lua"
	local dlc_o = real_dlc_root .. "/orcs/tome-orcs/data/locales/zh_hans.lua"
	local ok_alias = pcall(GenTokens.collect_sources, {
		tome_data_dir = real_tome_data,
		dlc_root = real_tome_data .. "/.",
		dlc_paths = { dlc_a, dlc_c, dlc_o },
	})
	assert(not ok_alias, "B4: collect_sources must fail when tome_data_dir and dlc_root resolve to the same physical directory")

	-- B4 negative check 4: missing DLC locale replaced by an unrelated locale file
	local ok_fake_dlc = pcall(GenTokens.collect_sources, {
		dlc_paths = { dlc_a, dlc_c, os.getenv("ADDON_ZH_HANS_LUA") or "data/locales/zh_hans.lua" },
	})
	assert(not ok_fake_dlc, "B4: collect_sources must fail when a required DLC locale (Orcs) is replaced by another file")

	-- B4 negative check 5: non-zh_hans locale file (e.g. official ko_KR.lua) must be rejected with zh_hans locale error
	local dlc_o_kr = real_dlc_root .. "/orcs/tome-orcs/data/locales/ko_KR.lua"
	local ok_kr, err_kr = pcall(GenTokens.collect_sources, {
		dlc_paths = { dlc_a, dlc_c, dlc_o_kr },
	})
	assert(not ok_kr and tostring(err_kr):find('must declare locale "zh_hans"', 1, true),
		"B4: collect_sources must reject non-zh_hans locale file (ko_KR.lua) with locale error, got: " .. tostring(err_kr))

	-- B4 negative check 6: forged empty Orcs section header prepended to another zh_hans locale must be rejected
	local forged_locale_path = os.tmpname()
	local core_zh_path = os.getenv("TOME_ZH_HANS_LUA") or "/workspace/t-engine4/game/modules/tome/data/locales/zh_hans.lua"
	local cf = assert(io.open(core_zh_path, "rb"))
	local core_zh_bytes = cf:read("*a")
	cf:close()
	local ff = assert(io.open(forged_locale_path, "wb"))
	ff:write('section "tome-orcs/data/general/npcs/orc.lua"\n')
	ff:write(core_zh_bytes)
	ff:close()
	local ok_forged, err_forged = pcall(GenTokens.collect_sources, {
		dlc_paths = { dlc_a, dlc_c, forged_locale_path },
	})
	os.remove(forged_locale_path)
	assert(not ok_forged and tostring(err_forged):find("is not a valid Ashes/Cults/Orcs DLC locale", 1, true),
		"B4: collect_sources must reject forged empty DLC section header with foreign entity entries, got: " .. tostring(err_forged))

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

	-- T04: Deterministic sample of 208,000 VALID epic candidates (16,000 valid outputs per epic cohort x 13 cohorts)
	local epic_slots_probed = 0
	local epic_valid_checked = 0
	for _, co in ipairs(cohorts_26) do
		if co.tier == "epic" then
			local total = BossNames.cohort_total(co.culture, co.sex, "epic")
			local stride = BossNames.stride_for(total)
			local k = 0
			local valid_in_cohort = 0
			while valid_in_cohort < 16000 do
				k = k + 1
				epic_slots_probed = epic_slots_probed + 1
				local idx = (k * stride) % total
				local personal, core = BossNames.candidate_at(co.culture, co.sex, "epic", idx)
				if personal then
					valid_in_cohort = valid_in_cohort + 1
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
	assert(epic_valid_checked == 208000, "T04 must audit 208,000 valid epic candidates")
	print(string.format("[PASS] T04 & T05: 0 R1-R3 collisions across %d unique given/surname segments and %d valid epic names (%d slots probed)",
		(function() local c = 0; for _ in pairs(checked_segments) do c = c + 1 end; return c end)(),
		epic_valid_checked, epic_slots_probed))
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
-- T07: string.tformat Real Semantics & All Real Chinese #rng# Templates from Locale Files
-- ============================================================================
local verified_real_templates = {}
do
	-- Load all real #rng# templates from the actual locale sources (S1, S2, S3, S4)
	local dlc_root = os.getenv("DLC_ROOT") or "/workspace/tome4-dlcs"
	local locale_paths = {
		os.getenv("TOME_ZH_HANS_LUA") or "/workspace/t-engine4/game/modules/tome/data/locales/zh_hans.lua",
		dlc_root .. "/ashes-urhrok/tome-ashes-urhrok/data/locales/zh_hans.lua",
		dlc_root .. "/cults/tome-cults/data/locales/zh_hans.lua",
		dlc_root .. "/orcs/tome-orcs/data/locales/zh_hans.lua",
		os.getenv("ADDON_ZH_HANS_LUA") or "data/locales/zh_hans.lua",
		os.getenv("ADDON_SUPPLEMENT_LUA") or "data/chn_supplement.lua",
	}
	local live_rng_map = {}
	local live_tformat_default = nil
	for _, lp in ipairs(locale_paths) do
		local env = setmetatable({
			locale = function() end,
			section = function() end,
			setFlag = function() end,
			forceFontPackage = function() end,
			t = function(src, dst, tag, order)
				if type(src) == "string" and type(dst) == "string" then
					if src == "%s the %s" and tag == "tformat" then
						live_tformat_default = { dst = dst, order = order }
					end
					if src:find("#rng#", 1, true) and tag == "_t" then
						live_rng_map[src] = dst
					end
				end
			end,
		}, { __index = _G })
		local chunk = assert(loadfile(lp))
		setfenv(chunk, env)
		chunk()
	end
	assert(live_tformat_default and live_tformat_default.dst == "%s %s", "failed to load real '%s the %s' tformat entry from locale files")
	assert(type(live_tformat_default.order) == "table" and live_tformat_default.order[1] == 2 and live_tformat_default.order[2] == 1)

	local real_templates = {
		{ en = "#rng# the Invader", zh = "入侵者#rng#", base = "orc archer", expected_pre = "入侵者", expected_suf = "" },
		{ en = "#rng# the Tidebender", zh = "驭潮者#rng#", base = "orc archer", expected_pre = "驭潮者", expected_suf = "" },
		{ en = "#rng# the Invoker", zh = "#rng#祈唤者", base = "human", expected_pre = "", expected_suf = "祈唤者" },
		{ en = "#rng# the Bringer of Doom", zh = "末日招来者#rng#", base = "major demon", expected_pre = "末日招来者", expected_suf = "" },
		{ en = "#rng# the Spawn of Urh'Rok", zh = "#rng# 乌鲁洛克的子嗣", base = "major demon", expected_pre = "", expected_suf = " 乌鲁洛克的子嗣" },
		{ en = "#rng# the Witherer", zh = "枯萎使者#rng#", base = "human", expected_pre = "枯萎使者", expected_suf = "" },
		{ en = "#rng# the Flamebringer", zh = "火焰使者#rng#", base = "human", expected_pre = "火焰使者", expected_suf = "" },
		{ en = "Grand Necromancer #rng#", zh = "高阶死灵法师#rng#", base = "human", expected_pre = "高阶死灵法师", expected_suf = "" },
		{ en = "#rng# the Guard", zh = "守卫 #rng#", base = "human", expected_pre = "守卫 ", expected_suf = "" },
		{ en = "Bandit Leader #rng#", zh = "盗贼首领 #rng#", base = "human", expected_pre = "盗贼首领 ", expected_suf = "" },
		{ en = "Sleeping #rng#", zh = "沉睡的 #rng#", base = "fire wyrm", expected_pre = "沉睡的 ", expected_suf = "" },
		{ en = "#rng# the Blightborn", zh = "枯萎之子#rng#", base = "orc archer", expected_pre = "枯萎之子", expected_suf = "" },
		{ en = "#rng# the Herald", zh = "传令官#rng#", base = "human", expected_pre = "传令官", expected_suf = "" },
	}
	for _, tc in ipairs(real_templates) do
		assert(live_rng_map[tc.en] == tc.zh, string.format("template pair mismatch in live locale: %q -> expected %q, got %q", tc.en, tc.zh, tostring(live_rng_map[tc.en])))
		locale_dict._t[tc.en] = tc.zh
		local base = make_base_actor{ name = tc.base }
		local orig = _t(tc.en):gsub("#rng#", "Arnold"):gsub("#base#", _t(tc.base))
		local pre, X, suf = BossNames.extract_personal_slot(orig, base, { name_scheme = _t(tc.en) })
		assert(pre == tc.expected_pre and X == "Arnold" and suf == tc.expected_suf,
			"failed template reconstruction for " .. tc.zh)
	end

	-- Also test every single valid #rng# template across all live locale files (all 32 keys)
	local all_rng_keys = {}
	for en, zh in pairs(live_rng_map) do
		local _, c = zh:gsub("#rng#", "")
		if c == 1 and not zh:gsub("#rng#", ""):gsub("#base#", ""):find("[#A-Za-z]") then
			all_rng_keys[#all_rng_keys + 1] = en
			locale_dict._t[en] = zh
		end
	end
	table.sort(all_rng_keys)
	assert(#all_rng_keys >= 30, "expected >= 30 valid #rng# templates in live locales, got " .. tostring(#all_rng_keys))
	local base_h = make_base_actor{ name = "human" }
	for _, en in ipairs(all_rng_keys) do
		local zh = _t(en)
		verified_real_templates[#verified_real_templates + 1] = zh
		local orig = zh:gsub("#rng#", "Arnold"):gsub("#base#", _t(base_h.name))
		local pre, X, suf = BossNames.extract_personal_slot(orig, base_h, { name_scheme = zh })
		assert(pre and X == "Arnold" and suf and (pre .. X .. suf) == orig, "failed live locale template: " .. en .. " => " .. zh)
	end

	-- Also verify template containing both #base# and #rng#
	local pre_b, X_b, suf_b = BossNames.extract_personal_slot("沉睡的火焰巨龙 Arnold", make_base_actor{ name = "fire wyrm" }, { name_scheme = "沉睡的#base# #rng#" })
	assert(pre_b == "沉睡的火焰巨龙 " and X_b == "Arnold" and suf_b == "")

	-- Verify default "%s the %s" with {2,1} order
	local pre, X, suf = BossNames.extract_personal_slot("人类 Arnold", base_h, {})
	assert(pre == "人类 " and X == "Arnold" and suf == "")

	-- Verify changing "%s the %s" translation to another permutation (e.g. "【%s】%s" with {2,1} or "%s（%s）" with {1,2}) works without code changes
	locale_dict.tformat["%s the %s"] = { dst = "【%s】%s", order = { 2, 1 } }
	local pre2, X2, suf2 = BossNames.extract_personal_slot("【人类】Arnold", base_h, {})
	assert(pre2 == "【人类】" and X2 == "Arnold" and suf2 == "")

	locale_dict.tformat["%s the %s"] = { dst = "%s（%s）", order = { 1, 2 } }
	local pre3, X3, suf3 = BossNames.extract_personal_slot("Arnold（人类）", base_h, {})
	assert(pre3 == "" and X3 == "Arnold" and suf3 == "（人类）")

	-- Restore standard translation
	locale_dict.tformat["%s the %s"] = { dst = "%s %s", order = { 2, 1 } }
	print(string.format("[PASS] T07: string.tformat semantics and %d real Chinese templates verified from live locale sources", #all_rng_keys))
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

	-- E08: name_scheme without #rng# ("腐化的 #base#") -> skip, zero state mutation
	local st08 = make_gamestate(true)
	local b08 = st08[fn_name](st08, base, { level = 10, rank = 3.5, name_scheme = "腐化的 #base#" })
	assert(b08.name == "腐化的 人类" and rawget(b08, "__chn_randboss_name") == nil and rawget(st08, "__chn_randboss_ledger") == nil)

	-- B2: Percent in template ("守卫%#rng#") on fresh state -> skip, must NOT create empty ledger
	local st_pct = make_gamestate(true)
	local b_pct = st_pct[fn_name](st_pct, base, { level = 10, rank = 3.2, name_scheme = "守卫%#rng#" })
	assert(rawget(b_pct, "__chn_randboss_name") == nil and rawget(st_pct, "__chn_randboss_ledger") == nil,
		"B2: failed validation on '守卫%#rng#' must not create empty ledger in state")

	-- E09: name_scheme with 2 #rng# -> skip
	local b09 = gs[fn_name](gs, base, { level = 10, rank = 3.5, name_scheme = "#rng#与#rng#" })
	assert(rawget(b09, "__chn_randboss_name") == nil)

	-- E10: Untranslated template "#rng# the Blightborn" -> skip
	local b10 = gs[fn_name](gs, base, { level = 10, rank = 3.5, name_scheme = "#rng# the Blightborn" })
	assert(b10.name:find("the Blightborn", 1, true) and rawget(b10, "__chn_randboss_name") == nil)

	-- E11 & B3: Untranslated base name (_t returns English) -> skip, even when template omits #base# (e.g. "守卫 #rng#")
	local un_base = make_base_actor{ name = "untranslated_wyrm", random_name_def = "cornac_#sex#" }
	local st11_a = make_gamestate(true)
	local b11 = st11_a[fn_name](st11_a, un_base, { level = 10, rank = 3.5 })
	assert(b11.name:find("untranslated_wyrm", 1, true) and rawget(b11, "__chn_randboss_name") == nil and rawget(st11_a, "__chn_randboss_ledger") == nil)
	local st11_b = make_gamestate(true)
	local b11_scheme = st11_b[fn_name](st11_b, un_base, { level = 10, rank = 3.2, name_scheme = "守卫 #rng#" })
	assert(rawget(b11_scheme, "__chn_randboss_name") == nil and rawget(st11_b, "__chn_randboss_ledger") == nil,
		"B3/E11: untranslated base name with '守卫 #rng#' must be skipped with zero ledger writes")

	-- E12 & B3: data.post modified b.name (or both b.name and b.unique to same-byte-length Chinese) -> skip
	local b12 = gs[fn_name](gs, base, {
		level = 10,
		rank = 3.5,
		post = function(b) b.name = "自定义首领名" end,
	})
	assert(b12.name == "自定义首领名" and rawget(b12, "__chn_randboss_name") == nil)

	-- B3 same-width post rename + unique sync ("守卫丙丁" -> "守卫甲乙"), including init-installed post, metatable __index post, and callable table post
	local st12_sw = make_gamestate(true)
	local saved_ng2_new = NameGenerator2.new
	NameGenerator2.new = function()
		return { generate = function() return "丙丁" end }
	end
	local caller_data_sw = {
		level = 10,
		rank = 3.2,
		name_scheme = "守卫#rng#",
		post = function(b)
			b.name = "守卫甲乙"
			b.unique = b.name
		end,
	}
	local orig_post_ref = caller_data_sw.post
	local b12_sw, id12_sw = st12_sw[fn_name](st12_sw, base, caller_data_sw)
	assert(caller_data_sw.post == orig_post_ref, "B3: caller data.post reference must remain intact")
	assert(b12_sw.name == "守卫甲乙" and b12_sw.unique == "守卫甲乙",
		"B3/E12: same-width post rename+unique sync must not be overwritten, got " .. tostring(b12_sw.name))
	assert(rawget(b12_sw, "__chn_randboss_name") == nil and rawget(st12_sw, "__chn_randboss_ledger") == nil)
	assert(id12_sw == b12_sw.define_as)

	-- B3 Round 2: post installed by data.init, inherited via __index, or callable table
	for _, post_mode in ipairs{ "init-installs-post", "inherited-post", "callable-post" } do
		local st_pm = make_gamestate(true)
		local d_pm = { level = 10, rank = 3.2, name_scheme = "守卫#rng#" }
		local patch_fn = function(b)
			b.name = "守卫甲乙"
			b.unique = b.name
		end
		if post_mode == "init-installs-post" then
			d_pm.init = function(t) t.post = patch_fn end
		elseif post_mode == "inherited-post" then
			setmetatable(d_pm, { __index = { post = patch_fn } })
		else
			d_pm.post = setmetatable({}, { __call = function(_, b) patch_fn(b) end })
		end
		local b_pm, id_pm = st_pm[fn_name](st_pm, base, d_pm)
		assert(b_pm.name == "守卫甲乙" and b_pm.unique == "守卫甲乙" and id_pm == b_pm.define_as,
			"B3(" .. post_mode .. "): post rename must be respected, got " .. tostring(b_pm.name))
		assert(rawget(b_pm, "__chn_randboss_name") == nil and rawget(st_pm, "__chn_randboss_ledger") == nil,
			"B3(" .. post_mode .. "): must not overwrite or record in ledger")
	end

	-- B3 Round 2: data.init cancels data.post by reference equality (both zh_hans and en_US) -> zero extra RNG calls
	for _, test_loc in ipairs{ "zh_hans", "en_US" } do
		config.settings.locale = test_loc
		local st_cancel = make_gamestate(true)
		local post_rng_calls = 0
		local function optional_post()
			post_rng_calls = post_rng_calls + 1
		end
		local d_cancel = {
			level = 10,
			rank = 3.2,
			name_scheme = "守卫#rng#",
			post = optional_post,
			init = function(d)
				assert(d.post == optional_post, "B3: init must observe original data.post reference")
				d.post = nil
			end,
		}
		st_cancel[fn_name](st_cancel, base, d_cancel)
		assert(post_rng_calls == 0 and d_cancel.post == nil, "B3(" .. test_loc .. "): cancelled post must not run")
	end
	config.settings.locale = "zh_hans"

	-- B3 Round 2: PUC Lua 5.1 coroutine.yield inside data.post must succeed without C-call boundary error
	do
		local st_co = make_gamestate(true)
		local d_co = {
			level = 10,
			rank = 3.2,
			name_scheme = "守卫#rng#",
			post = function()
				coroutine.yield("post_yield_marker")
			end,
		}
		local co = coroutine.create(function()
			return st_co[fn_name](st_co, base, d_co)
		end)
		local ok_y1, msg_y1 = coroutine.resume(co)
		assert(ok_y1 and msg_y1 == "post_yield_marker", "B3: coroutine yield inside post failed: " .. tostring(msg_y1))
		local ok_y2, b_co = coroutine.resume(co)
		assert(ok_y2 and type(b_co) == "table" and rawget(b_co, "__chn_randboss_name") ~= nil,
			"B3: coroutine resume after post yield failed")
	end

	-- B3 Round 3: b.rnd_boss_init(b, data) in legacy createRandomBoss (and if installed via data.init) must receive the real data table
	do
		for _, test_loc in ipairs{ "en_US", "zh_hans" } do
			config.settings.locale = test_loc
			local st_rbi = make_gamestate(true)
			local rbi_calls = 0
			local orig_rbi
			orig_rbi = function(b, opts)
				rbi_calls = rbi_calls + 1
				assert(rawequal(opts, st_rbi._test_d), "B3-R3(" .. test_loc .. "): b.rnd_boss_init must receive real data table")
				assert(rawget(opts, "no_loot_randart") == true, "B3-R3(" .. test_loc .. "): rawget(opts, 'no_loot_randart') must work")
				assert(rawequal(b.rnd_boss_init, orig_rbi), "B3-R3(" .. test_loc .. "): b.rnd_boss_init must be restored inside callback")
				local kcount = 0
				for _ in pairs(opts) do kcount = kcount + 1 end
				assert(kcount >= 3, "B3-R3(" .. test_loc .. "): pairs(opts) must iterate real data keys")
			end
			local base_rbi = make_base_actor{
				name = "人类",
				type = "humanoid",
				subtype = "human",
			}
			base_rbi.rnd_boss_init = orig_rbi
			base_rbi.clone = function(self_base)
				local saved_fn = self_base.rnd_boss_init
				local saved_clone = self_base.clone
				self_base.rnd_boss_init = nil
				self_base.clone = nil
				local c = Actor.clone(self_base)
				self_base.rnd_boss_init = saved_fn
				self_base.clone = saved_clone
				c.rnd_boss_init = saved_fn
				return c
			end
			local d_rbi = {
				level = 10,
				rank = 3.2,
				no_loot_randart = true,
			}
			st_rbi._test_d = d_rbi
			local b_rbi = st_rbi[fn_name](st_rbi, base_rbi, d_rbi)
			if fn_name == "createRandomBoss" then
				assert(rbi_calls == 1, "B3-R3(" .. test_loc .. "): b.rnd_boss_init must be invoked once in createRandomBoss")
			end
			assert(rawequal(b_rbi.rnd_boss_init, orig_rbi), "B3-R3(" .. test_loc .. "): b.rnd_boss_init must remain original function after return")
			assert(rawequal(base_rbi.rnd_boss_init, orig_rbi), "B3-R3(" .. test_loc .. "): base.rnd_boss_init must never be mutated")
		end
		config.settings.locale = "zh_hans"

		-- B3 Round 4:
		-- (a) createRandomBossNew must never wrap b.rnd_boss_init (neither during life_rating nor after an upstream error)
		-- (b) legacy createRandomBoss must restore b.rnd_boss_init if data.__newindex throws before the engine calls b.rnd_boss_init
		-- (c) explicit non-proxy second argument passed to b.rnd_boss_init must never be overwritten with creation options
		if fn_name == "createRandomBossNew" then
			for _, abort in ipairs{ false, true } do
				local st_new_rbi = make_gamestate(true)
				local actor_ref, retained_during, seen_arg
				local explicit_tag = { no_loot_randart = true }
				local handler = function(_b, opts)
					seen_arg = opts
				end
				local d_new_rbi = {
					level = 10,
					rank = 3.2,
					init = function(_d, b)
						actor_ref = b
						b.rnd_boss_init = handler
					end,
					life_rating = function(lr)
						retained_during = actor_ref.rnd_boss_init
						if abort then error("stop_in_life_rating", 0) end
						return lr
					end,
				}
				local ok_call, err_call = pcall(st_new_rbi.createRandomBossNew, st_new_rbi, base, d_new_rbi)
				assert(ok_call == not abort, "B3-R4: createRandomBossNew abort flag mismatch")
				if abort then
					assert(err_call == "stop_in_life_rating")
				end
				assert(rawequal(retained_during, handler), "B3-R4: createRandomBossNew must never wrap b.rnd_boss_init during execution")
				assert(rawequal(actor_ref.rnd_boss_init, handler), "B3-R4: createRandomBossNew must leave b.rnd_boss_init unwrapped after return/error")
				actor_ref:rnd_boss_init(explicit_tag)
				assert(rawequal(seen_arg, explicit_tag), "B3-R4: explicit argument to b.rnd_boss_init must be preserved")
			end
		elseif fn_name == "createRandomBoss" then
			local st_leg_abort = make_gamestate(true)
			local captured_actor, seen_arg
			local explicit_token = { custom = true }
			local handler = function(_b, opt)
				seen_arg = opt
			end
			local readonly_opts = setmetatable({
				level = 10,
				rank = 3.2,
				init = function(_d, b)
					captured_actor = b
					b.rnd_boss_init = handler
				end,
			}, {
				__newindex = function(_, key)
					if key == "nb_classes" then
						error("readonly_options_error", 0)
					end
				end,
			})
			local ok_leg, err_leg = pcall(st_leg_abort.createRandomBoss, st_leg_abort, base, readonly_opts)
			assert(not ok_leg and err_leg == "readonly_options_error", "B3-R4: readonly options error must propagate")
			assert(rawequal(captured_actor.rnd_boss_init, handler), "B3-R4: legacy createRandomBoss must restore b.rnd_boss_init on mid-execution error")
			captured_actor:rnd_boss_init(explicit_token)
			assert(rawequal(seen_arg, explicit_token), "B3-R4: later explicit argument to b.rnd_boss_init must be preserved")

			-- B3 Round 5 (a): data.nb_classes setter explicitly invokes b:rnd_boss_init(explicit_tag, "tail", nil) once before engine's normal call
			local st_r5_two = make_gamestate(true)
			local actor_r5, first_arg, second_arg
			local r5_calls, r5_rng_draws = 0, 0
			local r5_tag = { tag = "explicit" }
			local d_r5_two
			local r5_handler = function(_b, opt, ...)
				r5_calls = r5_calls + 1
				if r5_calls == 1 then
					first_arg = opt
					assert(select("#", ...) == 2 and (...) == "tail" and select(2, ...) == nil, "B3-R5: varargs on explicit call must be preserved")
				else
					second_arg = opt
					if not rawget(opt, "no_loot_randart") then
						r5_rng_draws = r5_rng_draws + 1
					end
				end
			end
			d_r5_two = setmetatable({
				level = 10,
				rank = 3.2,
				no_loot_randart = true,
				init = function(_d, b)
					actor_r5 = b
					b.rnd_boss_init = r5_handler
				end,
			}, {
				__newindex = function(t, k, v)
					rawset(t, k, v)
					if k == "nb_classes" then
						actor_r5:rnd_boss_init(r5_tag, "tail", nil)
					end
				end,
			})
			local boss_r5_two = st_r5_two:createRandomBoss(base, d_r5_two)
			assert(r5_calls == 2 and rawequal(first_arg, r5_tag) and rawequal(second_arg, d_r5_two) and r5_rng_draws == 0,
				"B3-R5: explicit call in nb_classes setter + subsequent engine call must both receive their expected args with 0 extra RNG")
			assert(rawequal(rawget(boss_r5_two, "rnd_boss_init"), r5_handler),
				"B3-R5: b.rnd_boss_init must remain original handler after both calls")

			-- B3 Round 5 (b): data.nb_classes getter (__index) throws a marker object -> same marker propagates and captured actor immediately has original handler
			local st_r5_get = make_gamestate(true)
			local captured_r5_get, observed_r5_later
			local err_marker = { marker = true }
			local later_arg = { later = true }
			local r5_get_handler = function(_b, opt)
				observed_r5_later = opt
			end
			local d_r5_get = setmetatable({
				level = 10,
				rank = 3.2,
				init = function(_d, b)
					captured_r5_get = b
					b.rnd_boss_init = r5_get_handler
				end,
			}, {
				__index = function(_, k)
					if k == "nb_classes" then
						error(err_marker, 0)
					end
				end,
			})
			local ok_r5_get, caught_r5 = pcall(st_r5_get.createRandomBoss, st_r5_get, base, d_r5_get)
			assert(not ok_r5_get and rawequal(caught_r5, err_marker) and captured_r5_get ~= nil,
				"B3-R5: nb_classes getter error marker must propagate unchanged")
			assert(rawequal(rawget(captured_r5_get, "rnd_boss_init"), r5_get_handler),
				"B3-R5: captured actor must immediately have original rnd_boss_init handler when nb_classes getter throws")
			captured_r5_get:rnd_boss_init(later_arg)
			assert(rawequal(observed_r5_later, later_arg), "B3-R5: subsequent explicit call after getter failure must preserve argument")
		end
	end

	-- Round 2 regression: bare "#rng#" template (empty prefix and suffix) must rename and record
	for _, bare_seed in ipairs{ "Seed438", "丙丁" } do
		local st_bare = make_gamestate(true)
		NameGenerator2.new = function()
			return { generate = function() return bare_seed end }
		end
		local b_bare, id_bare = st_bare[fn_name](st_bare, base, {
			level = 10,
			rank = 3.2,
			name_scheme = "#rng#",
		})
		assert(rawget(b_bare, "__chn_randboss_name") ~= nil and b_bare.name ~= bare_seed,
			"bare #rng# template must rename for seed " .. bare_seed)
		assert(b_bare.unique == bare_seed and id_bare == b_bare.define_as)
		assert(st_bare.__chn_randboss_ledger and st_bare.__chn_randboss_ledger.count == 1)
	end
	NameGenerator2.new = saved_ng2_new

	-- B1: Full Display Name R1 collision defense ("部落高阶大地法师#rng#" + "Seed438" must avoid fixed unique "部落高阶大地法师沃尔" and succeed)
	local st_b1 = make_gamestate(true)
	NameGenerator2.new = function()
		return { generate = function() return "Seed438" end }
	end
	local b_vor, id_vor = st_b1[fn_name](st_b1, base, {
		level = 10,
		rank = 3.2,
		name_scheme = "部落高阶大地法师#rng#",
	})
	NameGenerator2.new = saved_ng2_new
	assert(rawget(b_vor, "__chn_randboss_name") ~= nil, "B1: Vor prefix spawn must still succeed via next probe candidate")
	assert(b_vor.name ~= "部落高阶大地法师沃尔", "B1: full display name collided with fixed unique 部落高阶大地法师沃尔")
	assert(b_vor.name:sub(1, #"部落高阶大地法师") == "部落高阶大地法师" and b_vor.unique == "部落高阶大地法师Seed438" and id_vor == b_vor.define_as)
	assert(st_b1.__chn_randboss_ledger and st_b1.__chn_randboss_ledger.count == 1)

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

	-- E22 & B2: Corrupted rules data (empty pool / wrong type) on fresh state -> vanilla fallback, zero ledger creation
	local saved_human_init = rules.cultures.human.given.initials
	rules.cultures.human.given.initials = {}
	local st22_a = make_gamestate(true)
	local b22 = st22_a[fn_name](st22_a, base, { level = 10, rank = 3.2 })
	assert(rawget(b22, "__chn_randboss_name") == nil and rawget(st22_a, "__chn_randboss_ledger") == nil,
		"B2/E22: empty pool on fresh state must not create empty ledger")
	rules.cultures.human.given.initials = "corrupted_non_table"
	local st22_b = make_gamestate(true)
	local b22_b = st22_b[fn_name](st22_b, base, { level = 10, rank = 3.2 })
	assert(rawget(b22_b, "__chn_randboss_name") == nil and rawget(st22_b, "__chn_randboss_ledger") == nil)
	rules.cultures.human.given.initials = saved_human_init

	-- E23 & B2: rename / select / commit throws an internal error -> wrapper swallows it, returns full tuple, and leaves zero partial state
	local st23_sel = make_gamestate(true)
	local old_select = BossNames.select
	BossNames.select = function() error("injected selection error") end
	local b23_s, id23_s = st23_sel[fn_name](st23_sel, base, { level = 10, rank = 3.2 })
	BossNames.select = old_select
	assert(type(b23_s) == "table" and id23_s == b23_s.define_as)
	assert(rawget(b23_s, "__chn_randboss_name") == nil and rawget(st23_sel, "__chn_randboss_ledger") == nil,
		"B2/E23: selection failure must not leave empty ledger in fresh state")

	-- B2: Commit-phase fault injection 1: readonly ledger.count must not leave used[core] = true
	local st23_ro = make_gamestate(true)
	local used_ro = {}
	st23_ro.__chn_randboss_ledger = setmetatable({ version = 1, used = used_ro }, {
		__index = { count = 0 },
		__newindex = function() error("injected readonly count error") end,
	})
	local b23_ro, id23_ro = st23_ro[fn_name](st23_ro, base, { level = 10, rank = 3.2 })
	assert(id23_ro == b23_ro.define_as and rawget(b23_ro, "__chn_randboss_name") == nil and b23_ro.name == b23_ro.unique)
	assert(next(used_ro) == nil and st23_ro.__chn_randboss_ledger.count == 0 and rawget(st23_ro.__chn_randboss_ledger, "count") == nil,
		"B2: count write failure must not leave core reserved in ledger.used or materialize raw count")

	-- B2: Commit-phase fault injection 2: rules.version fault on second access must not leave b.name changed without meta
	local st23_ver = make_gamestate(true)
	local orig_ver = rules.version
	rules.version = nil
	local ver_reads = 0
	setmetatable(rules, {
		__index = function(_, k)
			if k == "version" then
				ver_reads = ver_reads + 1
				if ver_reads == 2 then error("injected meta assembly error") end
				return 1
			end
		end,
	})
	local b23_ver, id23_ver = st23_ver[fn_name](st23_ver, base, { level = 10, rank = 3.2 })
	setmetatable(rules, nil)
	rules.version = orig_ver
	assert(id23_ver == b23_ver.define_as)
	assert((rawget(b23_ver, "__chn_randboss_name") ~= nil and b23_ver.name == b23_ver.__chn_randboss_name.text and st23_ver.__chn_randboss_ledger.count == 1)
		or (rawget(b23_ver, "__chn_randboss_name") == nil and b23_ver.name == b23_ver.unique and rawget(st23_ver, "__chn_randboss_ledger") == nil),
		"B2: commit must be atomic (either full rename+meta+ledger or zero mutation)")

	-- B2: Commit-phase fault injection 3: used.__newindex writes key before throwing -> rollback must remove orphaned key
	local st23_late = make_gamestate(true)
	local used_late = setmetatable({}, {
		__newindex = function(t, k, v)
			rawset(t, k, v)
			error("injected late used error")
		end,
	})
	st23_late.__chn_randboss_ledger = { version = 1, used = used_late, count = 0 }
	local b23_late, id23_late = st23_late[fn_name](st23_late, base, { level = 10, rank = 3.2 })
	assert(id23_late == b23_late.define_as and rawget(b23_late, "__chn_randboss_name") == nil and b23_late.name == b23_late.unique)
	assert(next(used_late) == nil and st23_late.__chn_randboss_ledger.count == 0,
		"B2: late used error must roll back orphaned core reservation")

	-- B2: Commit-phase fault injection 4: inherited count (rawget == nil) + readonly used -> must not materialize raw count = 0
	local st23_inh = make_gamestate(true)
	local used_inh = setmetatable({}, {
		__newindex = function() error("injected readonly used error") end,
	})
	local ledger_inh = setmetatable({ version = 1, used = used_inh }, { __index = { count = 0 } })
	st23_inh.__chn_randboss_ledger = ledger_inh
	local b23_inh, id23_inh = st23_inh[fn_name](st23_inh, base, { level = 10, rank = 3.2 })
	assert(id23_inh == b23_inh.define_as and rawget(b23_inh, "__chn_randboss_name") == nil and b23_inh.name == b23_inh.unique)
	assert(next(used_inh) == nil and rawget(ledger_inh, "count") == nil,
		"B2: readonly used failure must not materialize rawget(ledger, 'count')")

	-- B2 Round 3: Commit-phase fault injection 5: delegated count backing store where __newindex writes store[k] = v then throws on increment
	local st23_del = make_gamestate(true)
	local backing_store = { count = 0 }
	local used_del = {}
	local ledger_del = setmetatable({ version = 1, used = used_del }, {
		__index = backing_store,
		__newindex = function(_, k, v)
			backing_store[k] = v
			if k == "count" and v > 0 then
				error("injected post-write delegated count error")
			end
		end,
	})
	st23_del.__chn_randboss_ledger = ledger_del
	local b23_del, id23_del = st23_del[fn_name](st23_del, base, { level = 10, rank = 3.2 })
	assert(id23_del == b23_del.define_as and rawget(b23_del, "__chn_randboss_name") == nil and b23_del.name == b23_del.unique)
	assert(ledger_del.count == 0 and backing_store.count == 0 and rawget(ledger_del, "count") == nil and next(used_del) == nil,
		"B2-R3: delegated count post-write failure must roll back backing store count to 0 without materializing raw count")

	-- B2 Round 4: Commit-phase fault injection 6: monotonic delegated count backing store that rejects decreasing writes must be rejected pre-commit with zero writes
	local st23_mono = make_gamestate(true)
	local mono_backing = { count = 0 }
	local mono_writes = {}
	local mono_used = {}
	local ledger_mono = setmetatable({ version = 1, used = mono_used }, {
		__index = mono_backing,
		__newindex = function(_, k, v)
			mono_writes[#mono_writes + 1] = v
			if v < mono_backing[k] then
				error("counter must not decrease")
			end
			mono_backing[k] = v
			error("injected failure after storing increment")
		end,
	})
	st23_mono.__chn_randboss_ledger = ledger_mono
	local b23_mono, id23_mono = st23_mono[fn_name](st23_mono, base, { level = 10, rank = 3.2 })
	assert(id23_mono == b23_mono.define_as and rawget(b23_mono, "__chn_randboss_name") == nil and b23_mono.name == b23_mono.unique)
	assert(#mono_writes == 0 and ledger_mono.count == 0 and mono_backing.count == 0 and rawget(ledger_mono, "count") == nil and next(mono_used) == nil,
		"B2-R4: monotonic delegated ledger must be rejected pre-commit with zero writes")

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

	-- NPC audit regression tests (4 culture/sex matching fixes):
	do
		-- (d) 2-argument BossNames.culture_of(base, state) backward compatibility
		local c2_h, s2_h = BossNames.culture_of({ type = "humanoid", subtype = "human", female = true }, {})
		assert(c2_h == "human" and s2_h == "female", "2-arg culture_of backward compatibility failed for human/female")
		local c2_m, s2_m = BossNames.culture_of({ type = "humanoid", subtype = "human" }, {})
		assert(c2_m == "human" and s2_m == "male", "2-arg culture_of backward compatibility failed for human/male")

		-- (c) humanoid/elf -> elf, humanoid/yaech -> yeek, aquatic/demon -> demon (2-arg, 3-arg, and end-to-end)
		local c_elf2, s_elf2 = BossNames.culture_of({ type = "humanoid", subtype = "elf", female = true }, {})
		assert(c_elf2 == "elf" and s_elf2 == "female", "humanoid/elf 2-arg must map to elf/female")
		local c_elf3, s_elf3 = BossNames.culture_of({ type = "humanoid" }, {}, { type = "humanoid", subtype = "elf", female = false })
		assert(c_elf3 == "elf" and s_elf3 == "male", "humanoid/elf 3-arg must map to elf/male")

		local c_yaech2, s_yaech2 = BossNames.culture_of({ type = "humanoid", subtype = "yaech", female = false }, {})
		assert(c_yaech2 == "yeek" and s_yaech2 == "male", "humanoid/yaech 2-arg must map to yeek/male")
		local c_yaech3, s_yaech3 = BossNames.culture_of({ type = "humanoid", subtype = "yaech" }, {}, { female = true })
		assert(c_yaech3 == "yeek" and s_yaech3 == "female", "humanoid/yaech 3-arg must map to yeek/female")

		local c_aqd2, s_aqd2 = BossNames.culture_of({ type = "aquatic", subtype = "demon" }, {})
		assert(c_aqd2 == "demon" and s_aqd2 == "none", "aquatic/demon 2-arg must map to demon/none")
		local c_aqd3, s_aqd3 = BossNames.culture_of({ type = "aquatic" }, {}, { type = "aquatic", subtype = "demon" })
		assert(c_aqd3 == "demon" and s_aqd3 == "none", "aquatic/demon 3-arg must map to demon/none")

		local st_sub = make_gamestate(true)
		local b_elf_e2e = st_sub[fn_name](st_sub, make_base_actor{ name = "永恒精灵", type = "humanoid", subtype = "elf", female = true }, { level = 10, rank = 3.2 })
		assert(b_elf_e2e.__chn_randboss_name and b_elf_e2e.__chn_randboss_name.culture == "elf" and b_elf_e2e.__chn_randboss_name.sex == "female",
			"end-to-end humanoid/elf must use elf/female pool")
		local b_yaech_e2e = st_sub[fn_name](st_sub, make_base_actor{ name = "夺心魔心灵杀手", type = "humanoid", subtype = "yaech", female = false }, { level = 10, rank = 3.2 })
		assert(b_yaech_e2e.__chn_randboss_name and b_yaech_e2e.__chn_randboss_name.culture == "yeek" and b_yaech_e2e.__chn_randboss_name.sex == "male",
			"end-to-end humanoid/yaech must use yeek/male pool")
		local b_aqd_e2e = st_sub[fn_name](st_sub, make_base_actor{ name = "恶魔", type = "aquatic", subtype = "demon" }, { level = 10, rank = 3.2 })
		assert(b_aqd_e2e.__chn_randboss_name and b_aqd_e2e.__chn_randboss_name.culture == "demon" and b_aqd_e2e.__chn_randboss_name.sex == "none",
			"end-to-end aquatic/demon must use demon/none pool")

		-- (a) Simulate resolvers.racial_visual setting b.female = true during b:resolve() while base.female == nil,
		-- and b.female = false explicitly overriding base.female = true
		local orig_resolve = Actor.resolve
		local base_no_female = make_base_actor{ name = "人类", type = "humanoid", subtype = "human", female = nil }
		Actor.resolve = function(self_actor)
			self_actor.female = true
		end
		local st_res_f = make_gamestate(true)
		local b_res_f = st_res_f[fn_name](st_res_f, base_no_female, { level = 10, rank = 3.2 })
		Actor.resolve = orig_resolve
		assert(base_no_female.female == nil and b_res_f.female == true)
		assert(b_res_f.__chn_randboss_name and b_res_f.__chn_randboss_name.culture == "human" and b_res_f.__chn_randboss_name.sex == "female",
			"resolved b.female = true with base.female == nil must select female pool")

		local base_female_true = make_base_actor{ name = "人类", type = "humanoid", subtype = "human", female = true }
		Actor.resolve = function(self_actor)
			self_actor.female = false
		end
		local st_res_m = make_gamestate(true)
		local b_res_m = st_res_m[fn_name](st_res_m, base_female_true, { level = 10, rank = 3.2 })
		Actor.resolve = orig_resolve
		assert(base_female_true.female == true and b_res_m.female == false)
		assert(b_res_m.__chn_randboss_name and b_res_m.__chn_randboss_name.culture == "human" and b_res_m.__chn_randboss_name.sex == "male",
			"resolved b.female = false must override base.female = true and select male pool")

		-- (b) Simulate dynamic resolver subtype on base (base.subtype = { __resolver = "rngtable" }) resolved to b.subtype = "shalore"
		local base_dyn_sub = make_base_actor{
			name = "永恒精灵",
			type = "humanoid",
			subtype = { __resolver = "rngtable", "shalore", "thalore" },
			female = nil,
		}
		Actor.resolve = function(self_actor)
			self_actor.subtype = "shalore"
			self_actor.female = true
		end
		local st_dyn_sub = make_gamestate(true)
		local b_dyn_sub = st_dyn_sub[fn_name](st_dyn_sub, base_dyn_sub, { level = 10, rank = 3.5 })
		Actor.resolve = orig_resolve
		assert(type(base_dyn_sub.subtype) == "table" and b_dyn_sub.subtype == "shalore")
		assert(b_dyn_sub.__chn_randboss_name and b_dyn_sub.__chn_randboss_name.culture == "elf" and b_dyn_sub.__chn_randboss_name.sex == "female" and b_dyn_sub.__chn_randboss_name.tier == "epic",
			"resolved b.subtype = 'shalore' from dynamic resolver table on base must select elf pool")
	end

	forbid_random_and_time()
end

run_edge_case_tests("createRandomBoss")
run_edge_case_tests("createRandomBossNew")
print("[PASS] T14 & T17: All edge cases (E01–E32, B1–B3) and createRandomBossNew equivalence verified")

-- ============================================================================
-- T15: Mixed Stress Test (1,000 spawns across all 26 cohorts x 8 templates = 208 combinations)
-- ============================================================================
do
	local t0 = orig_os_clock()
	local st = {}
	_G.game = { state = st }

	local culture_bases = {
		{ culture = "human", sex = "male", name = "human", type = "humanoid", subtype = "human", random_name_def = "cornac_#sex#", female = false },
		{ culture = "human", sex = "female", name = "human", type = "humanoid", subtype = "human", random_name_def = "higher_#sex#", female = true },
		{ culture = "elf", sex = "male", name = "eternal elf", type = "humanoid", subtype = "shalore", random_name_def = "shalore_#sex#", female = false },
		{ culture = "elf", sex = "female", name = "eternal elf", type = "humanoid", subtype = "thalore", random_name_def = "thalore_#sex#", female = true },
		{ culture = "dwarf", sex = "male", name = "dwarven earthwarden", type = "humanoid", subtype = "dwarf", random_name_def = "dwarf_#sex#", female = false },
		{ culture = "dwarf", sex = "female", name = "dwarven earthwarden", type = "humanoid", subtype = "dwarf", random_name_def = "dwarf_#sex#", female = true },
		{ culture = "halfling", sex = "male", name = "halfling slinger", type = "humanoid", subtype = "halfling", random_name_def = "halfling_#sex#", female = false },
		{ culture = "halfling", sex = "female", name = "halfling slinger", type = "humanoid", subtype = "halfling", random_name_def = "halfling_#sex#", female = true },
		{ culture = "yeek", sex = "male", name = "yeek mindslayer", type = "humanoid", subtype = "yeek", random_name_def = "yeek_#sex#", female = false },
		{ culture = "yeek", sex = "female", name = "yeek mindslayer", type = "humanoid", subtype = "yeek", random_name_def = "yeek_#sex#", female = true },
		{ culture = "orc", sex = "none", name = "orc archer", type = "humanoid", subtype = "orc", random_name_def = nil },
		{ culture = "demon", sex = "none", name = "major demon", type = "demon", subtype = "major", random_name_def = "demon" },
		{ culture = "monster", sex = "none", name = "brown bear", type = "animal", subtype = "bear", random_name_def = nil },
	}
	local templates = {
		false, -- default "%s the %s" template
		"守卫 #rng#",
		"扰乱者#rng#",
		"入侵者#rng#",
		"火焰使者#rng#",
		"盗贼首领 #rng#",
		"沉睡的#base# #rng#",
		"#rng# 乌鲁洛克的子嗣",
	}
	local tier_ranks = {
		{ tier = "rare", rank = 3.2 },
		{ tier = "epic", rank = 4.0 },
	}

	-- Build all 13 x 2 x 8 = 208 (cohort x template) combinations and step with coprime stride 53
	local combos = {}
	for _, cb in ipairs(culture_bases) do
		for _, tr in ipairs(tier_ranks) do
			for t_idx, tmpl in ipairs(templates) do
				combos[#combos + 1] = {
					cb = cb,
					tier = tr.tier,
					rank = tr.rank,
					tmpl = tmpl,
					t_idx = t_idx,
				}
			end
		end
	end
	assert(#combos == 208)

	local lcg = 314159265
	local function next_token_num()
		lcg = (lcg * 1664525 + 1013904223) % 4294967296
		return math.floor(lcg / 65536)
	end

	local seen_cores = {}
	local hit_cohorts = {}
	local hit_templates = {}
	local hit_combos = {}
	local D = live_collision.sources.D

	for i = 1, 1000 do
		local c_idx = ((i - 1) * 53) % #combos + 1
		local entry = combos[c_idx]
		hit_combos[c_idx] = true
		hit_cohorts[entry.cb.culture .. ":" .. entry.cb.sex .. ":" .. entry.tier] = true
		hit_templates[entry.t_idx] = (hit_templates[entry.t_idx] or 0) + 1

		local base = make_base_actor(entry.cb)
		local tmpl = entry.tmpl or nil
		local rk = entry.rank
		local raw_rng_token = "Rand" .. tostring(i) .. "x" .. tostring(next_token_num())
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
		assert(meta.culture == entry.cb.culture and meta.sex == entry.cb.sex and meta.tier == entry.tier)
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
	local n_cohorts_hit = 0
	for _ in pairs(hit_cohorts) do n_cohorts_hit = n_cohorts_hit + 1 end
	local n_templates_hit = 0
	for _ in pairs(hit_templates) do n_templates_hit = n_templates_hit + 1 end
	local n_combos_hit = 0
	for _ in pairs(hit_combos) do n_combos_hit = n_combos_hit + 1 end
	assert(n_cohorts_hit == 26, "T15 must hit all 26 cohorts, hit " .. tostring(n_cohorts_hit))
	assert(n_templates_hit == #templates, "T15 must hit all 8 templates (including default), hit " .. tostring(n_templates_hit))
	assert(n_combos_hit == 208, "T15 must hit all 208 cohort x template combinations, hit " .. tostring(n_combos_hit))
	assert(st.__chn_randboss_ledger.count == 1000)
	assert(elapsed < 3.0, string.format("T15 mixed stress test took %.3fs (>= 3.0s limit)", elapsed))

	-- Full 26 cohorts x (32 live templates + default = 33) = 858 combinations through real createRandomBoss
	rng_seed = 20260858
	_G.rng = make_recording_rng()
	local st_858 = make_gamestate(true)
	_G.game = { state = st_858 }
	local live_33 = { false }
	for _, zh_t in ipairs(verified_real_templates) do
		live_33[#live_33 + 1] = zh_t
	end
	assert(#live_33 == 33, "expected 33 templates (default + 32 live locale templates), got " .. tostring(#live_33))
	local seen_858 = {}
	local count_858 = 0
	for _, cb in ipairs(culture_bases) do
		for _, tr in ipairs(tier_ranks) do
			for _, tmpl in ipairs(live_33) do
				local base_i = make_base_actor(cb)
				local b_i, id_i = st_858:createRandomBoss(base_i, {
					level = 10,
					rank = tr.rank,
					name_scheme = tmpl or nil,
				})
				local m_i = assert(rawget(b_i, "__chn_randboss_name"), "858 matrix failed on " .. cb.culture .. "/" .. cb.sex .. "/" .. tr.tier)
				assert(m_i.culture == cb.culture and m_i.sex == cb.sex and m_i.tier == tr.tier)
				assert(b_i:getName() == m_i.text and id_i == b_i.define_as)
				assert(not seen_858[m_i.core], "duplicate core in 858 matrix: " .. m_i.core)
				seen_858[m_i.core] = true
				count_858 = count_858 + 1
			end
		end
	end
	forbid_random_and_time()
	assert(count_858 == 858 and st_858.__chn_randboss_ledger.count == 858)
	print(string.format("[PASS] T15: 1,000 mixed spawns (%d combos) + all 26 x 33 = %d live template matrix -> 0 collisions, elapsed=%.3fs (< 3s)",
		n_combos_hit, count_858, elapsed))
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
