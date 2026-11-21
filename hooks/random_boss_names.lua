local ok_rules, rules = pcall(dofile, "/data-chn-mod/chn_randboss_names.lua")
if not ok_rules then rules = dofile("data/chn_randboss_names.lua") end
local M = {
	rules = rules,
	MAX_LEDGER = 8192,
	BASE_STRIDE = 2971,
	MAX_PROBES = 50000,
}

local function zh()
	return config and config.settings and config.settings.locale == "zh_hans"
end

local function plain_label(s)
	return type(s) == "string" and #s > 0 and not s:find("[#~&%%%c<>]")
end

local function utf8_valid(s)
	if type(s) ~= "string" or #s == 0 then
		return false
	end
	local i = 1
	local len = #s
	while i <= len do
		local b = s:byte(i)
		if b < 128 then
			i = i + 1
		elseif b >= 194 and b <= 223 then
			if i + 1 > len then return false end
			local b2 = s:byte(i + 1)
			if b2 < 128 or b2 > 191 then return false end
			i = i + 2
		elseif b >= 224 and b <= 239 then
			if i + 2 > len then return false end
			local b2, b3 = s:byte(i + 1, i + 2)
			if b2 < 128 or b2 > 191 or b3 < 128 or b3 > 191 then return false end
			if b == 224 and b2 < 160 then return false end
			if b == 237 and b2 > 159 then return false end
			i = i + 3
		elseif b >= 240 and b <= 244 then
			if i + 3 > len then return false end
			local b2, b3, b4 = s:byte(i + 1, i + 3)
			if b2 < 128 or b2 > 191 or b3 < 128 or b3 > 191 or b4 < 128 or b4 > 191 then return false end
			if b == 240 and b2 < 144 then return false end
			if b == 244 and b2 > 143 then return false end
			i = i + 4
		else
			return false
		end
	end
	return true
end

local function utf8_chars(s)
	local chars = {}
	if type(s) ~= "string" then
		return chars
	end
	local i = 1
	local len = #s
	while i <= len do
		local b = s:byte(i)
		local clen = 1
		if b >= 240 then
			clen = 4
		elseif b >= 224 then
			clen = 3
		elseif b >= 192 then
			clen = 2
		end
		chars[#chars + 1] = s:sub(i, i + clen - 1)
		i = i + clen
	end
	return chars
end

local function hash31(key)
	-- Small integer arithmetic, exact under the Lua 5.1 number model.
	local h = 0
	for i = 1, #key do
		h = (h * 131 + key:byte(i)) % 2147483647
	end
	return h
end

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

function M.stride_for(total)
	if type(total) ~= "number" or total <= 1 then
		return 1
	end
	local s = M.BASE_STRIDE
	if s % 2 == 0 then
		s = s + 1
	end
	while gcd(s, total) ~= 1 do
		s = s + 2
	end
	return s
end

function M.tier_of(rank)
	local threshold = type(rules) == "table" and type(rules.rank_epic_threshold) == "number" and rules.rank_epic_threshold or 3.5
	if type(rank) == "number" and rank >= threshold then
		return "epic"
	end
	return "rare"
end

function M.culture_of(base, state)
	local cultures = type(rules) == "table" and type(rules.cultures) == "table" and rules.cultures or nil
	local def_map = type(rules) == "table" and type(rules.def_to_culture) == "table" and rules.def_to_culture or {}
	local sub_map = type(rules) == "table" and type(rules.humanoid_subtype_to_culture) == "table" and rules.humanoid_subtype_to_culture or {}
	local default_c = type(rules) == "table" and type(rules.default_culture) == "string" and rules.default_culture or "monster"

	local culture
	local def
	if type(base) == "table" and type(base.random_name_def) == "string" and base.random_name_def ~= "" then
		def = base.random_name_def
	elseif type(state) == "table" and type(state.birth) == "table" and type(state.birth.world_base_random_name_def) == "string" and state.birth.world_base_random_name_def ~= "" then
		def = state.birth.world_base_random_name_def
	end

	if type(def) == "string" then
		local prefix = def:match("^(.-)_#sex#") or def:match("^(.-)#sex#") or def
		culture = def_map[prefix]
	end

	if not culture and type(base) == "table" then
		if base.type == "demon" then
			culture = "demon"
		elseif base.type == "humanoid" and type(base.subtype) == "string" then
			culture = sub_map[base.subtype]
		end
	end

	if not culture then
		culture = default_c
	end

	local cdef = cultures and cultures[culture] or nil
	local sex = "none"
	if type(cdef) == "table" and cdef.gendered == true then
		sex = (type(base) == "table" and base.female) and "female" or "male"
	end
	return culture, sex
end

function M.core_of(personal)
	if type(personal) ~= "string" then
		return ""
	end
	local sep = type(rules) == "table" and type(rules.separator) == "string" and rules.separator or "·"
	local eq = type(rules) == "table" and type(rules.phonetic_equiv) == "table" and rules.phonetic_equiv or {}
	local chars = utf8_chars(personal)
	local out = {}
	for i = 1, #chars do
		local c = chars[i]
		if c ~= sep then
			out[#out + 1] = eq[c] or c
		end
	end
	return table.concat(out)
end

local function given_pools(culture, sex)
	if type(rules) ~= "table" or type(rules.cultures) ~= "table" then
		return nil
	end
	local cdef = rules.cultures[culture]
	if type(cdef) ~= "table" or type(cdef.given) ~= "table" then
		return nil
	end
	local g = cdef.given
	local I = g.initials
	local M_pool = g.middles
	local finals_tbl = g.finals
	local F_key = cdef.gendered and (sex == "female" and "female" or "male") or "none"
	local F = type(finals_tbl) == "table" and finals_tbl[F_key] or nil
	if type(I) ~= "table" or #I == 0 or type(M_pool) ~= "table" or #M_pool == 0 or type(F) ~= "table" or #F == 0 then
		return nil
	end
	return I, M_pool, F
end

local function surname_pools(culture)
	if type(rules) ~= "table" or type(rules.cultures) ~= "table" then
		return nil
	end
	local cdef = rules.cultures[culture]
	if type(cdef) ~= "table" or type(cdef.surname) ~= "table" then
		return nil
	end
	local s = cdef.surname
	local SI, SM, SF = s.initials, s.middles, s.finals
	if type(SI) ~= "table" or #SI == 0 or type(SM) ~= "table" or #SM == 0 or type(SF) ~= "table" or #SF == 0 then
		return nil
	end
	return SI, SM, SF
end

function M.cohort_total(culture, sex, tier)
	local I, M_pool, F = given_pools(culture, sex)
	if not I then
		return 0, 0, 0
	end
	local given_raw = (#I * #F) + (#I * #M_pool * #F)
	if tier == "rare" then
		return given_raw, given_raw, 0
	elseif tier == "epic" then
		local SI, SM, SF = surname_pools(culture)
		if not SI then
			return 0, given_raw, 0
		end
		local surname_raw = (#SI * #SF) + (#SI * #SM * #SF)
		return given_raw * surname_raw, given_raw, surname_raw
	end
	return 0, 0, 0
end

local function decode_segment_chars(I, M_pool, F, idx)
	local nF = #F
	local raw_2 = #I * nF
	if idx < raw_2 then
		local i_idx = math.floor(idx / nF) + 1
		local f_idx = (idx % nF) + 1
		return I[i_idx], F[f_idx], nil
	else
		local rem = idx - raw_2
		local mf = #M_pool * nF
		local i_idx = math.floor(rem / mf) + 1
		local rem2 = rem % mf
		local m_idx = math.floor(rem2 / nF) + 1
		local f_idx = (rem2 % nF) + 1
		return I[i_idx], M_pool[m_idx], F[f_idx]
	end
end

local function check_char_valid(c, approved, banned, reject_female, female_only)
	if type(c) ~= "string" or c == "" then return false end
	if approved and not approved[c] then return false end
	if banned and banned[c] then return false end
	if reject_female and female_only and female_only[c] then return false end
	return true
end

local function validate_and_build_segment(c1, c2, c3, max_len, reject_female)
	local len = c3 ~= nil and 3 or 2
	if len > max_len then return nil, nil end
	local approved = type(rules.approved_chars) == "table" and rules.approved_chars or nil
	local banned = type(rules.banned_chars) == "table" and rules.banned_chars or nil
	local banned_init = type(rules.banned_initial_chars) == "table" and rules.banned_initial_chars or nil
	local female_only = type(rules.female_only_chars) == "table" and rules.female_only_chars or nil
	if type(c1) ~= "string" or (banned_init and banned_init[c1]) then
		return nil, nil
	end
	if not check_char_valid(c1, approved, banned, reject_female, female_only)
		or not check_char_valid(c2, approved, banned, reject_female, female_only)
	then
		return nil, nil
	end
	if c1 == c2 then return nil, nil end
	local eq = type(rules.phonetic_equiv) == "table" and rules.phonetic_equiv or {}
	local nc1 = eq[c1] or c1
	local nc2 = eq[c2] or c2
	if nc1 == nc2 then return nil, nil end

	if c3 ~= nil then
		if not check_char_valid(c3, approved, banned, reject_female, female_only) then
			return nil, nil
		end
		if c3 == c1 or c3 == c2 then return nil, nil end
		local nc3 = eq[c3] or c3
		if nc3 == nc1 or nc3 == nc2 then return nil, nil end
		return c1 .. c2 .. c3, nc1 .. nc2 .. nc3, c1, c2, c3, nc1, nc2, nc3
	else
		return c1 .. c2, nc1 .. nc2, c1, c2, nil, nc1, nc2, nil
	end
end

local cached_bsubs_ref = nil
local cached_ftoks_ref = nil
local cached_2char_set = nil
local cached_3char_set = nil
local cached_long_list = nil

local function get_compiled_filters()
	local bsubs = type(rules.banned_substrings) == "table" and rules.banned_substrings or nil
	local ftoks = type(rules.fixed_name_tokens) == "table" and rules.fixed_name_tokens or nil
	if bsubs == cached_bsubs_ref and ftoks == cached_ftoks_ref and cached_2char_set then
		return cached_2char_set, cached_3char_set, cached_long_list
	end
	local s2, s3, long_l = {}, {}, {}
	local function add_list(lst)
		if not lst then return end
		for i = 1, #lst do
			local w = lst[i]
			if type(w) == "string" and w ~= "" then
				local blen = #w
				if blen == 6 then
					s2[w] = true
				elseif blen == 9 then
					s3[w] = true
				else
					long_l[#long_l + 1] = w
				end
			end
		end
	end
	add_list(bsubs)
	add_list(ftoks)
	cached_bsubs_ref = bsubs
	cached_ftoks_ref = ftoks
	cached_2char_set = s2
	cached_3char_set = s3
	cached_long_list = long_l
	return s2, s3, long_l
end

local function check_segment_filters(str, core_str, c1, c2, c3, nc1, nc2, nc3)
	if not plain_label(str) then
		return false
	end
	local excluded = type(rules.excluded_exact) == "table" and rules.excluded_exact or nil
	if excluded and (excluded[str] or excluded[core_str]) then
		return false
	end
	local s2, s3, long_l = get_compiled_filters()
	if c3 == nil then
		if s2[str] or s2[core_str] then return false end
	else
		if s3[str] or s3[core_str] then return false end
		if s2[c1 .. c2] or s2[c2 .. c3] or s2[nc1 .. nc2] or s2[nc2 .. nc3] then
			return false
		end
	end
	for i = 1, #long_l do
		local sub = long_l[i]
		if str:find(sub, 1, true) or core_str:find(sub, 1, true) then
			return false
		end
	end
	return true
end

local function check_epic_combined_filters(personal, unsep, core_str)
	if not plain_label(personal) then
		return false
	end
	local excluded = type(rules.excluded_exact) == "table" and rules.excluded_exact or nil
	if excluded and (excluded[personal] or excluded[unsep] or excluded[core_str]) then
		return false
	end
	local bsubs = type(rules.banned_substrings) == "table" and rules.banned_substrings or nil
	if bsubs then
		for i = 1, #bsubs do
			local sub = bsubs[i]
			if type(sub) == "string" and sub ~= "" then
				if personal:find(sub, 1, true) or unsep:find(sub, 1, true) or core_str:find(sub, 1, true) then
					return false
				end
			end
		end
	end
	local ftoks = type(rules.fixed_name_tokens) == "table" and rules.fixed_name_tokens or nil
	if ftoks then
		for i = 1, #ftoks do
			local tok = ftoks[i]
			if type(tok) == "string" and tok ~= "" then
				if unsep:find(tok, 1, true) or core_str:find(tok, 1, true) then
					return false
				end
			end
		end
	end
	return true
end

function M.candidate_at(culture, sex, tier, idx)
	if type(idx) ~= "number" or idx < 0 then
		return nil, nil
	end
	local total, given_raw, surname_raw = M.cohort_total(culture, sex, tier)
	if total <= 0 then
		return nil, nil
	end
	local norm = idx % total
	local max_g = type(rules.max_given_chars) == "number" and rules.max_given_chars or 3
	local I, M_pool, F = given_pools(culture, sex)
	if not I then
		return nil, nil
	end
	local reject_female_given = (sex ~= "female")

	if tier == "rare" then
		local c1, c2, c3 = decode_segment_chars(I, M_pool, F, norm)
		local personal, core, a1, a2, a3, na1, na2, na3 = validate_and_build_segment(c1, c2, c3, max_g, reject_female_given)
		if not personal then
			return nil, nil
		end
		if not check_segment_filters(personal, core, a1, a2, a3, na1, na2, na3) then
			return nil, nil
		end
		return personal, core
	elseif tier == "epic" then
		local SI, SM, SF = surname_pools(culture)
		if not SI or surname_raw <= 0 then
			return nil, nil
		end
		local max_s = type(rules.max_surname_chars) == "number" and rules.max_surname_chars or 3
		local sep = type(rules.separator) == "string" and rules.separator or "·"
		local g_idx = math.floor(norm / surname_raw)
		local s_idx = norm % surname_raw
		local gc1, gc2, gc3 = decode_segment_chars(I, M_pool, F, g_idx)
		local given_str, given_core, ga1, ga2, ga3, gna1, gna2, gna3 = validate_and_build_segment(gc1, gc2, gc3, max_g, reject_female_given)
		if not given_str then
			return nil, nil
		end
		local sc1, sc2, sc3 = decode_segment_chars(SI, SM, SF, s_idx)
		local sur_str, sur_core, sa1, sa2, sa3, sna1, sna2, sna3 = validate_and_build_segment(sc1, sc2, sc3, max_s, true)
		if not sur_str then
			return nil, nil
		end
		-- Ensure no shared raw or normalized characters between given and surname
		if sa1 == ga1 or sa1 == ga2 or (ga3 and sa1 == ga3) then return nil, nil end
		if sa2 == ga1 or sa2 == ga2 or (ga3 and sa2 == ga3) then return nil, nil end
		if sa3 and (sa3 == ga1 or sa3 == ga2 or (ga3 and sa3 == ga3)) then return nil, nil end
		if sna1 == gna1 or sna1 == gna2 or (gna3 and sna1 == gna3) then return nil, nil end
		if sna2 == gna1 or sna2 == gna2 or (gna3 and sna2 == gna3) then return nil, nil end
		if sna3 and (sna3 == gna1 or sna3 == gna2 or (gna3 and sna3 == gna3)) then return nil, nil end

		if not check_segment_filters(given_str, given_core, ga1, ga2, ga3, gna1, gna2, gna3) then
			return nil, nil
		end
		if not check_segment_filters(sur_str, sur_core, sa1, sa2, sa3, sna1, sna2, sna3) then
			return nil, nil
		end
		local personal = given_str .. sep .. sur_str
		local unsep = given_str .. sur_str
		local core = given_core .. sur_core
		if not check_epic_combined_filters(personal, unsep, core) then
			return nil, nil
		end
		return personal, core
	end
	return nil, nil
end

local function is_valid_ledger_table(raw)
	if type(raw) ~= "table" or getmetatable(raw) ~= nil then
		return false
	end
	local version = rawget(raw, "version")
	local count = rawget(raw, "count")
	local used = rawget(raw, "used")
	if version ~= 1
		or type(used) ~= "table"
		or getmetatable(used) ~= nil
		or type(count) ~= "number"
		or count < 0
		or count > M.MAX_LEDGER
		or math.floor(count) ~= count
	then
		return false
	end
	return true
end

local function inspect_ledger(state)
	if type(state) ~= "table" then
		return nil, false
	end
	local raw = rawget(state, "__chn_randboss_ledger")
	if raw == nil then
		return {
			version = 1,
			count = 0,
			used = {},
		}, true
	end
	if not is_valid_ledger_table(raw) then
		return nil, false
	end
	return raw, false
end

function M.ensure_ledger(state)
	local ledger, is_new = inspect_ledger(state)
	if not ledger then
		return nil
	end
	if is_new then
		rawset(state, "__chn_randboss_ledger", ledger)
	end
	return ledger
end

local function collect_party_names()
	local names = {}
	local g = rawget(_G, "game")
	local party = type(g) == "table" and rawget(g, "party") or nil
	local members = type(party) == "table" and rawget(party, "members") or nil
	if type(members) == "table" then
		for actor, _ in pairs(members) do
			if type(actor) == "table" then
				local n = rawget(actor, "name")
				if type(n) == "string" and n ~= "" then
					names[n] = true
					names[M.core_of(n)] = true
				end
			end
		end
	end
	local player = type(g) == "table" and rawget(g, "player") or nil
	if type(player) == "table" then
		local n = rawget(player, "name")
		if type(n) == "string" and n ~= "" then
			names[n] = true
			names[M.core_of(n)] = true
		end
	end
	return names
end

local function normalize_party_set(party_names)
	if type(party_names) ~= "table" then
		return {}
	end
	local set = {}
	for k, v in pairs(party_names) do
		if type(k) == "string" and v then
			set[k] = true
			set[M.core_of(k)] = true
		end
		if type(v) == "string" and v ~= "" then
			set[v] = true
			set[M.core_of(v)] = true
		end
	end
	return set
end

function M.select(culture, sex, tier, seed_key, ledger, party_names, prefix, suffix)
	if type(ledger) ~= "table" or type(ledger.used) ~= "table" or type(ledger.count) ~= "number" then
		return nil, nil, nil
	end
	local total = M.cohort_total(culture, sex, tier)
	if not total or total <= 0 then
		return nil, nil, nil
	end
	local start = hash31(tostring(seed_key or "")) % total
	local stride = M.stride_for(total)
	local max_probes = math.min(total, M.MAX_PROBES)
	local used = ledger.used
	local party_set = normalize_party_set(party_names)
	local recorded = ledger.count < M.MAX_LEDGER
	local has_affix = type(prefix) == "string" or type(suffix) == "string"
	local pre = type(prefix) == "string" and prefix or ""
	local suf = type(suffix) == "string" and suffix or ""
	local excluded = type(rules) == "table" and type(rules.excluded_exact) == "table" and rules.excluded_exact or nil

	for step = 0, max_probes - 1 do
		local idx = (start + step * stride) % total
		local personal, core = M.candidate_at(culture, sex, tier, idx)
		if personal and core then
			if not used[core] and not party_set[personal] and not party_set[core] then
				local ok = true
				if has_affix then
					local full_name = pre .. personal .. suf
					if (excluded and excluded[full_name]) or party_set[full_name] then
						ok = false
					end
				end
				if ok then
					return personal, core, recorded, step + 1
				end
			end
		end
	end
	return nil, nil, nil
end

function M.extract_personal_slot(orig, base, data)
	if type(orig) ~= "string" or orig == "" or type(base) ~= "table" or type(base.name) ~= "string" or base.name == "" then
		return nil
	end
	local t_fn = rawget(_G, "_t")
	local tbase = type(t_fn) == "function" and t_fn(base.name) or base.name
	if type(tbase) ~= "string" or tbase == "" then
		return nil
	end
	-- §2.2 rule 7 / E11: Reject if translated base name remains untranslated (contains ASCII letters), even when scheme omits #base#.
	if tbase:find("[A-Za-z]") then
		return nil
	end

	local scheme = type(data) == "table" and data.name_scheme or nil
	local probe
	if scheme ~= nil then
		if type(scheme) ~= "string" or scheme == "" then
			return nil
		end
		local _, rng_count = scheme:gsub("#rng#", "")
		if rng_count ~= 1 then
			return nil
		end
		if scheme:find("\1", 1, true) then
			return nil
		end
		probe = scheme:gsub("#rng#", "\1"):gsub("#base#", function() return tbase end)
	else
		local tmpl = "%s the %s"
		if type(tmpl.tformat) ~= "function" then
			return nil
		end
		local ok, res = pcall(tmpl.tformat, tmpl, "\1", tbase)
		if not ok or type(res) ~= "string" then
			return nil
		end
		probe = res
	end

	local p1 = probe:find("\1", 1, true)
	if not p1 or probe:find("\1", p1 + 1, true) then
		return nil
	end
	local prefix = probe:sub(1, p1 - 1)
	local suffix = probe:sub(p1 + 1)

	-- Reject if template remains untranslated (contains ASCII letters).
	if (prefix .. suffix):find("[A-Za-z]") then
		return nil
	end

	if #orig <= #prefix + #suffix then
		return nil
	end
	if orig:sub(1, #prefix) ~= prefix then
		return nil
	end
	if #suffix > 0 and orig:sub(#orig - #suffix + 1) ~= suffix then
		return nil
	end
	local X = orig:sub(#prefix + 1, #orig - #suffix)
	if X == "" then
		return nil
	end

	-- Forward reconstruction verification
	local forward
	if scheme ~= nil then
		forward = scheme:gsub("#rng#", function() return X end):gsub("#base#", function() return tbase end)
	else
		local tmpl = "%s the %s"
		local ok, res = pcall(tmpl.tformat, tmpl, X, tbase)
		if not ok or type(res) ~= "string" then
			return nil
		end
		forward = res
	end
	if forward ~= orig then
		return nil
	end

	return prefix, X, suffix
end

function M.audit_cohort(culture, sex, tier)
	tier = tier or "rare"
	local total = M.cohort_total(culture, sex, tier)
	if not total or total <= 0 or tier ~= "rare" then
		return {
			raw_slots = total or 0,
			valid_count = 0,
			core_count = 0,
			list = {},
			core_list = {},
		}
	end
	local seen_personal = {}
	local seen_core = {}
	local list = {}
	local core_list = {}
	local valid_count = 0
	for idx = 0, total - 1 do
		local personal, core = M.candidate_at(culture, sex, "rare", idx)
		if personal and core then
			valid_count = valid_count + 1
			if not seen_personal[personal] then
				seen_personal[personal] = true
				list[#list + 1] = personal
			end
			if not seen_core[core] then
				seen_core[core] = true
				core_list[#core_list + 1] = core
			end
		end
	end
	return {
		raw_slots = total,
		valid_count = valid_count,
		core_count = #core_list,
		list = list,
		core_list = core_list,
	}
end

function M.surname_audit(culture)
	local SI, SM, SF = surname_pools(culture)
	if not SI then
		return {
			raw_slots = 0,
			valid_count = 0,
			core_count = 0,
			list = {},
			core_list = {},
		}
	end
	local total = (#SI * #SF) + (#SI * #SM * #SF)
	local max_s = type(rules.max_surname_chars) == "number" and rules.max_surname_chars or 3
	local seen_sur = {}
	local seen_core = {}
	local list = {}
	local core_list = {}
	local valid_count = 0
	for idx = 0, total - 1 do
		local c1, c2, c3 = decode_segment_chars(SI, SM, SF, idx)
		local sur, core, a1, a2, a3, na1, na2, na3 = validate_and_build_segment(c1, c2, c3, max_s, true)
		if sur and check_segment_filters(sur, core, a1, a2, a3, na1, na2, na3) then
			valid_count = valid_count + 1
			if not seen_sur[sur] then
				seen_sur[sur] = true
				list[#list + 1] = sur
			end
			if not seen_core[core] then
				seen_core[core] = true
				core_list[#core_list + 1] = core
			end
		end
	end
	return {
		raw_slots = total,
		valid_count = valid_count,
		core_count = #core_list,
		list = list,
		core_list = core_list,
	}
end

function M.rename(b, base, data, state)
	if not zh() then return end
	if type(b) ~= "table" or b.randboss ~= true then return end
	local orig = rawget(b, "name")
	if type(orig) ~= "string" or orig == "" or rawget(b, "unique") ~= orig then return end
	local expected_id = "RND_BOSS_" .. (orig:upper():gsub("[^A-Z]", "_"))
	if b.define_as ~= expected_id then return end
	local meta = rawget(b, "__chn_randboss_name")
	if type(meta) == "table" and meta.text == orig then return end
	local prefix, X, suffix = M.extract_personal_slot(orig, base, data)
	if not prefix then return end
	local affixes = prefix .. suffix
	if (affixes ~= "" and not plain_label(affixes)) or not utf8_valid(prefix .. "名" .. suffix) then return end

	local tier = M.tier_of(b.rank)
	local culture, sex = M.culture_of(base, state)
	local ledger, is_new_ledger = inspect_ledger(state)
	if ledger == nil then return end

	local rule_ver = type(rules) == "table" and rules.version or 1
	local scheme_tag = (type(data) == "table" and type(data.name_scheme) == "string") and data.name_scheme or "default"
	local key = table.concat({
		"rb",
		tostring(rule_ver),
		tostring(tier),
		tostring(culture),
		tostring(sex),
		orig,
		tostring(type(base) == "table" and base.name or ""),
		tostring(b.define_as),
		scheme_tag,
	}, "\0")

	local personal, core, recorded = M.select(culture, sex, tier, key, ledger, collect_party_names(), prefix, suffix)
	if not personal or not core then return end
	local new_name = prefix .. personal .. suffix
	if not plain_label(new_name) or not utf8_valid(new_name) then return end
	if type(rules) == "table" and type(rules.excluded_exact) == "table" and rules.excluded_exact[new_name] then
		return
	end

	-- Pre-assemble metadata before any mutation
	local new_meta = {
		version = rule_ver,
		text = new_name,
		original = orig,
		core = core,
		tier = tier,
		culture = culture,
		sex = sex,
		recorded = recorded == true,
	}

	-- Atomic commit: update ledger used[core] then count with full rollback on failure, before attaching ledger or setting meta & name
	if recorded then
		local had_core = (ledger.used[core] ~= nil)
		local raw_count = rawget(ledger, "count")
		local prev_count = ledger.count
		local next_count = prev_count + 1
		local ok_used, err_used = pcall(function()
			ledger.used[core] = true
		end)
		if not ok_used then
			if not had_core then
				pcall(rawset, ledger.used, core, nil)
				pcall(function() ledger.used[core] = nil end)
			end
			error(err_used, 0)
		end
		local ok_cnt, err_cnt = pcall(function()
			ledger.count = next_count
		end)
		if not ok_cnt then
			if not had_core then
				pcall(rawset, ledger.used, core, nil)
				pcall(function() ledger.used[core] = nil end)
			end
			if raw_count == nil then
				pcall(rawset, ledger, "count", nil)
			else
				pcall(rawset, ledger, "count", raw_count)
			end
			local ok_chk, cur_count = pcall(function() return ledger.count end)
			if ok_chk and cur_count ~= prev_count then
				pcall(function() ledger.count = prev_count end)
				if raw_count == nil then
					pcall(rawset, ledger, "count", nil)
				end
			end
			error(err_cnt, 0)
		end
	end
	if is_new_ledger then
		rawset(state, "__chn_randboss_ledger", ledger)
	end
	rawset(b, "__chn_randboss_name", new_meta)
	b.name = new_name
end

return M
