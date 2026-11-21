-- Generate fixed_name_tokens, excluded_exact, and fixed_full_names for data/chn_randboss_names.lua (§5.3).
-- Can be run standalone (luajit tests/gen_randboss_collision_tokens.lua) to print Lua table literals,
-- or required/dofiled by tests/test_random_boss_names.lua to verify synchronization against live sources.

local M = {}

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

local SEPS = {
	["·"] = true, ["•"] = true, ["，"] = true, [","] = true, ["、"] = true,
	[" "] = true, ["　"] = true, ["「"] = true, ["」"] = true, ["『"] = true,
	["』"] = true, ["（"] = true, ["）"] = true, ["("] = true, [")"] = true,
	["："] = true, [":"] = true, ["的"] = true, ["之"] = true, ["“"] = true,
	["”"] = true, ["\""] = true,
}

local TERM_CATS = {
	["T.PN.PERSON"] = true,
	["T.PN.PLACE"] = true,
	["T.PN.RACE"] = true,
	["T.PN.FACTION"] = true,
	["T.PN.WORLD"] = true,
}

local function read_file_bytes(path, label)
	if type(path) ~= "string" or path == "" then
		error("missing required path for " .. tostring(label or "source"), 0)
	end
	local f = io.open(path, "rb")
	if not f then
		error("missing or unreadable required source (" .. tostring(label or "source") .. "): " .. tostring(path), 0)
	end
	local content = f:read("*a")
	f:close()
	if type(content) ~= "string" then
		error("failed to read source (" .. tostring(label or "source") .. "): " .. tostring(path), 0)
	end
	return content
end

local function fnv_fingerprint(s)
	local h1 = 2166136261
	local h2 = #s
	for i = 1, #s do
		h1 = ((h1 + s:byte(i)) * 16777619) % 4294967296
		h2 = (h2 * 131 + s:byte(i)) % 2147483647
	end
	return string.format("%d:%08x:%08x", #s, h1, h2)
end

local function load_locale_file(path, label, D, entity_trans, all_trans, seen_fingerprints)
	local content = read_file_bytes(path, label)
	local fp = fnv_fingerprint(content)
	if seen_fingerprints[fp] then
		error(string.format("duplicate locale source content detected for %s (%s duplicates %s)",
			tostring(label), tostring(path), tostring(seen_fingerprints[fp])), 0)
	end
	seen_fingerprints[fp] = tostring(label) .. ":" .. tostring(path)

	local count = 0
	local sections = {}
	local file_entities = {}
	local env = setmetatable({
		locale = function() end,
		section = function(sec)
			if type(sec) == "string" then
				sections[sec] = true
			end
		end,
		setFlag = function() end,
		forceFontPackage = function() end,
		t = function(src, dst, tag)
			if type(src) == "string" and type(dst) == "string" and dst ~= "" then
				local aset = all_trans[src]
				if not aset then
					aset = {}
					all_trans[src] = aset
				end
				aset[dst] = true
				if tag == "entity name" then
					local eset = entity_trans[src]
					if not eset then
						eset = {}
						entity_trans[src] = eset
					end
					eset[dst] = true
					file_entities[src] = dst
					D[dst] = true
					count = count + 1
				end
			end
		end,
	}, { __index = _G })
	local chunk = assert(loadstring(content, path))
	setfenv(chunk, env)
	chunk()
	return count, sections, file_entities
end

local function canonicalize_dir_path(dir, label)
	if type(dir) ~= "string" or dir == "" then
		error("missing directory path for " .. tostring(label), 0)
	end
	local check_cmd = string.format("cd -P -- %q 2>/dev/null && pwd -P", dir)
	local cp = io.popen(check_cmd, "r")
	local real_dir = cp and cp:read("*l") or nil
	if cp then cp:close() end
	if not real_dir or real_dir == "" then
		error("required source directory does not exist (" .. tostring(label) .. "): " .. tostring(dir), 0)
	end
	return real_dir
end

local function list_files_in_dir(dir, pattern_args, label)
	local real_dir = canonicalize_dir_path(dir, label)
	local cmd = string.format("find %q %s 2>/dev/null", real_dir, pattern_args)
	local p = assert(io.popen(cmd, "r"))
	local files = {}
	for line in p:lines() do
		if line ~= "" then
			files[#files + 1] = line
		end
	end
	p:close()
	table.sort(files)
	return files, real_dir
end

-- Lexical scanner for Lua source files to extract top-level literal `name` where `unique = true` inside balanced `newEntity{...}` constructors.
local function match_long_bracket(s, pos)
	if s:byte(pos) ~= 91 then return nil end -- '['
	local i = pos + 1
	while s:byte(i) == 61 do -- '='
		i = i + 1
	end
	if s:byte(i) ~= 91 then return nil end -- '['
	local eq_count = i - pos - 1
	local close_pat = "]" .. string.rep("=", eq_count) .. "]"
	local close_start, close_end = s:find(close_pat, i + 1, true)
	if not close_start then
		return #s + 1, s:sub(i + 1)
	end
	return close_end + 1, s:sub(i + 1, close_start - 1)
end

local function tokenize_lua(s)
	local tokens = {}
	local vals = {}
	local n = #s
	local i = 1
	while i <= n do
		local b = s:byte(i)
		-- Whitespace
		if b == 32 or b == 9 or b == 10 or b == 13 or b == 11 or b == 12 then
			i = i + 1
		-- Comment
		elseif b == 45 and s:byte(i + 1) == 45 then -- '--'
			local next_i = match_long_bracket(s, i + 2)
			if next_i then
				i = next_i
			else
				local nl = s:find("\n", i + 2, true)
				i = nl and (nl + 1) or (n + 1)
			end
		-- Long string
		elseif b == 91 and (s:byte(i + 1) == 91 or s:byte(i + 1) == 61) then
			local next_i, body = match_long_bracket(s, i)
			if next_i then
				tokens[#tokens + 1] = "STRING"
				vals[#vals + 1] = body
				i = next_i
			else
				tokens[#tokens + 1] = "["
				vals[#vals + 1] = "["
				i = i + 1
			end
		-- Short string
		elseif b == 34 or b == 39 then -- '"' or '\''
			local quote = b
			local j = i + 1
			local buf = {}
			while j <= n do
				local cj = s:byte(j)
				if cj == quote then
					j = j + 1
					break
				elseif cj == 92 then -- '\\'
					local next_c = s:byte(j + 1)
					if next_c == 34 or next_c == 39 or next_c == 92 then
						buf[#buf + 1] = string.char(next_c)
						j = j + 2
					elseif next_c == 110 then
						buf[#buf + 1] = "\n"
						j = j + 2
					elseif next_c == 116 then
						buf[#buf + 1] = "\t"
						j = j + 2
					elseif next_c == 114 then
						buf[#buf + 1] = "\r"
						j = j + 2
					elseif next_c then
						buf[#buf + 1] = "\\" .. string.char(next_c)
						j = j + 2
					else
						j = j + 1
					end
				else
					buf[#buf + 1] = s:sub(j, j)
					j = j + 1
				end
			end
			tokens[#tokens + 1] = "STRING"
			vals[#vals + 1] = table.concat(buf)
			i = j
		-- Identifier
		elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
			local j = i + 1
			while j <= n do
				local cj = s:byte(j)
				if (cj >= 65 and cj <= 90) or (cj >= 97 and cj <= 122) or (cj >= 48 and cj <= 57) or cj == 95 then
					j = j + 1
				else
					break
				end
			end
			local word = s:sub(i, j - 1)
			tokens[#tokens + 1] = word
			vals[#vals + 1] = word
			i = j
		-- Two-dot '..'
		elseif b == 46 and s:byte(i + 1) == 46 then
			tokens[#tokens + 1] = ".."
			vals[#vals + 1] = ".."
			i = i + 2
		else
			local ch = s:sub(i, i)
			tokens[#tokens + 1] = ch
			vals[#vals + 1] = ch
			i = i + 1
		end
	end
	return tokens, vals
end

local function is_field_terminator(tok)
	return tok == "," or tok == ";" or tok == "}"
end

function M.extract_fixed_entities_from_source(s)
	local results = {}
	if type(s) ~= "string" or not s:find("newEntity", 1, true) or not s:find("unique", 1, true) then
		return results
	end
	local w, vals = tokenize_lua(s)
	local nw = #w
	for j = 1, nw do
		if w[j] == "newEntity" then
			local k = j + 1
			if w[k] == "(" then k = k + 1 end
			if w[k] == "{" then
				local depth = 1
				local block_depth = 0
				local loop_cond = false
				local name = nil
				local is_unique = false
				k = k + 1
				while k <= nw and depth > 0 do
					local a = w[k]
					local prev = w[k - 1]
					if depth == 1 and block_depth == 0 and (prev == "{" or prev == "," or prev == ";") and w[k + 1] == "=" then
						if a == "unique" then
							if w[k + 2] == "true" and is_field_terminator(w[k + 3]) then
								is_unique = true
							elseif w[k + 2] == "false" and is_field_terminator(w[k + 3]) then
								is_unique = false
							end
						elseif a == "name" then
							local h = k + 2
							if w[h] == "_t" or w[h] == "_nt" then h = h + 1 end
							local had_paren = false
							if w[h] == "(" then
								had_paren = true
								h = h + 1
							end
							local v_tok = w[h]
							local v_val = vals[h]
							local z = h + 1
							if had_paren and w[z] == ")" then z = z + 1 end
							if v_tok == "STRING" and is_field_terminator(w[z]) then
								name = v_val
							end
						end
					end
					if a == "{" or a == "(" then
						depth = depth + 1
					elseif a == "}" or a == ")" then
						depth = depth - 1
					elseif a == "for" or a == "while" then
						loop_cond = true
					elseif a == "do" then
						if loop_cond then
							loop_cond = false
						end
						block_depth = block_depth + 1
					elseif a == "function" or a == "if" or a == "repeat" then
						block_depth = block_depth + 1
					elseif a == "end" or a == "until" then
						if block_depth > 0 then
							block_depth = block_depth - 1
						end
					end
					k = k + 1
				end
				if is_unique and type(name) == "string" and name ~= "" then
					results[#results + 1] = name
				end
			end
		end
	end
	return results
end

local DLC_SIGNATURES = {
	["ashes-urhrok"] = {
		section_prefix = "tome-ashes-urhrok/",
		min_entities = 30,
	},
	["cults"] = {
		section_prefix = "tome-cults/",
		min_entities = 150,
	},
	["orcs"] = {
		section_prefix = "tome-orcs/",
		min_entities = 300,
	},
}

local function identify_dlc_locale(sections, count)
	for dlc_id, sig in pairs(DLC_SIGNATURES) do
		if count >= sig.min_entities then
			for sec in pairs(sections) do
				if sec:sub(1, #sig.section_prefix) == sig.section_prefix then
					return dlc_id
				end
			end
		end
	end
	return nil
end

function M.collect_sources(opts)
	opts = opts or {}
	local s1_path = opts.addon_zh or os.getenv("ADDON_ZH_HANS_LUA") or "data/locales/zh_hans.lua"
	local s2_path = opts.addon_supp or os.getenv("ADDON_SUPPLEMENT_LUA") or "data/chn_supplement.lua"
	local s3_path = opts.tome_zh or os.getenv("TOME_ZH_HANS_LUA") or "/workspace/t-engine4/game/modules/tome/data/locales/zh_hans.lua"
	local dlc_root = opts.dlc_root or os.getenv("DLC_ROOT") or "/workspace/tome4-dlcs"
	local dlc_zh_env = opts.dlc_zhs or os.getenv("DLC_ZH_HANS_LUAS")
	local term_dir = opts.term_dir or os.getenv("TERMINOLOGY_DIR") or "/workspace/tome4-chinese-translation/terminology"
	local tome_data_dir = opts.tome_data_dir or os.getenv("TOME_DATA_DIR") or "/workspace/t-engine4/game/modules/tome/data"

	local D = {}
	local entity_trans = {}
	local all_trans = {}
	local seen_locale_fps = {}

	local s1_count = load_locale_file(s1_path, "S1(addon_zh)", D, entity_trans, all_trans, seen_locale_fps)
	assert(s1_count > 0, "S1 loaded 0 entity names from " .. tostring(s1_path))

	local s2_count = load_locale_file(s2_path, "S2(addon_supplement)", D, entity_trans, all_trans, seen_locale_fps)

	local s3_count = load_locale_file(s3_path, "S3(tome_zh)", D, entity_trans, all_trans, seen_locale_fps)
	assert(s3_count > 0, "S3 loaded 0 entity names from " .. tostring(s3_path))

	local dlc_paths = {}
	if type(opts.dlc_paths) == "table" then
		for _, p in ipairs(opts.dlc_paths) do
			dlc_paths[#dlc_paths + 1] = p
		end
	elseif dlc_zh_env and dlc_zh_env ~= "" then
		for p in dlc_zh_env:gmatch("[^:]+") do
			dlc_paths[#dlc_paths + 1] = p
		end
	else
		dlc_paths = {
			dlc_root .. "/ashes-urhrok/tome-ashes-urhrok/data/locales/zh_hans.lua",
			dlc_root .. "/cults/tome-cults/data/locales/zh_hans.lua",
			dlc_root .. "/orcs/tome-orcs/data/locales/zh_hans.lua",
		}
	end
	assert(#dlc_paths == 3, "S4 requires exactly 3 distinct DLC locale files (ashes-urhrok, cults, orcs), got " .. tostring(#dlc_paths))
	local s4_count = 0
	local s4_per_dlc = {}
	local seen_dlc_ids = {}
	for i, p in ipairs(dlc_paths) do
		local c, sections = load_locale_file(p, "S4(dlc_" .. tostring(i) .. ")", D, entity_trans, all_trans, seen_locale_fps)
		assert(c > 0, "S4 loaded 0 entity names from " .. tostring(p))
		local dlc_id = identify_dlc_locale(sections, c)
		if not dlc_id then
			error("S4 locale file is not a valid Ashes/Cults/Orcs DLC locale: " .. tostring(p), 0)
		end
		if seen_dlc_ids[dlc_id] then
			error("S4 duplicate DLC locale identity (" .. dlc_id .. "): " .. tostring(p), 0)
		end
		seen_dlc_ids[dlc_id] = p
		s4_per_dlc[i] = c
		s4_count = s4_count + c
	end
	for req_dlc in pairs(DLC_SIGNATURES) do
		if not seen_dlc_ids[req_dlc] then
			error("S4 missing required DLC locale for " .. req_dlc, 0)
		end
	end

	-- S5: terminology/*.tsv
	local tsv_files = list_files_in_dir(term_dir, "-maxdepth 1 -name '*.tsv'", "S5(terminology_dir)")
	assert(#tsv_files > 0, "S5 found no .tsv files in " .. tostring(term_dir))
	local s5_count = 0
	for _, tsv in ipairs(tsv_files) do
		local content = read_file_bytes(tsv, "S5(tsv)")
		local first_line = true
		local src_idx, tgt_idx, cat_idx = 1, 2, 3
		for line in content:gmatch("[^\n]+") do
			line = line:gsub("\r$", "")
			local cols = {}
			for col in (line .. "\t"):gmatch("([^\t]*)\t") do
				cols[#cols + 1] = col
			end
			if first_line then
				for ci, cname in ipairs(cols) do
					if cname == "source" then src_idx = ci
					elseif cname == "target" then tgt_idx = ci
					elseif cname == "category" then cat_idx = ci end
				end
				first_line = false
			else
				local target, cat = cols[tgt_idx], cols[cat_idx]
				if TERM_CATS[cat] and type(target) == "string" and target ~= "" then
					D[target] = true
					s5_count = s5_count + 1
				end
			end
		end
	end
	assert(s5_count > 0, "S5 loaded 0 terminology entries from " .. tostring(term_dir))

	-- S6: fixed unique entities from TOME_DATA_DIR and DLC_ROOT (both must exist, resolve to distinct physical directories, and contain definitions)
	local core_lua_files, real_core_dir = list_files_in_dir(tome_data_dir, "-name '*.lua' ! -path '*/locales/*'", "S6(tome_data_dir)")
	assert(#core_lua_files > 0, "S6 found no lua files in tome_data_dir: " .. tostring(tome_data_dir))
	local dlc_lua_files, real_dlc_dir = list_files_in_dir(dlc_root, "-name '*.lua' ! -path '*/locales/*'", "S6(dlc_root)")
	assert(#dlc_lua_files > 0, "S6 found no lua files in dlc_root: " .. tostring(dlc_root))
	if real_core_dir == real_dlc_dir or real_dlc_dir:sub(1, #real_core_dir + 1) == real_core_dir .. "/" or real_core_dir:sub(1, #real_dlc_dir + 1) == real_dlc_dir .. "/" then
		error(string.format("S6 tome_data_dir (%s) and dlc_root (%s) must resolve to distinct physical directories", tostring(real_core_dir), tostring(real_dlc_dir)), 0)
	end

	local s6_unique_zh = {}
	local s6_en_set = {}
	local s6_def_count = 0
	local s6_core_defs = 0
	local s6_dlc_defs = 0

	local function scan_entity_files(file_list, is_core)
		for _, lf in ipairs(file_list) do
			local s = read_file_bytes(lf, "S6(entity_lua)")
			local names = M.extract_fixed_entities_from_source(s)
			for _, name in ipairs(names) do
				s6_def_count = s6_def_count + 1
				if is_core then
					s6_core_defs = s6_core_defs + 1
				else
					s6_dlc_defs = s6_dlc_defs + 1
				end
				s6_en_set[name] = true
				local zset = all_trans[name]
				if zset then
					for zh in pairs(zset) do
						if zh ~= "" then
							D[zh] = true
							s6_unique_zh[zh] = true
						end
					end
				end
			end
		end
	end

	scan_entity_files(core_lua_files, true)
	scan_entity_files(dlc_lua_files, false)

	assert(s6_core_defs > 0, "S6 found 0 fixed unique entity definitions in tome_data_dir: " .. tostring(tome_data_dir))
	assert(s6_dlc_defs > 0, "S6 found 0 fixed unique entity definitions in dlc_root: " .. tostring(dlc_root))

	local s6_count = 0
	for _ in pairs(s6_unique_zh) do s6_count = s6_count + 1 end
	local s6_en_count = 0
	for _ in pairs(s6_en_set) do s6_en_count = s6_en_count + 1 end

	assert(s6_count >= 200, "S6 resolved fewer than 200 unique entity Chinese names: " .. tostring(s6_count))
	assert(s1_count + s3_count >= 3000, "S1 + S3 entity names < 3000: " .. tostring(s1_count + s3_count))

	local T = {}
	for dst in pairs(D) do
		local cur = {}
		for _, ch in ipairs(utf8_chars(dst)) do
			if SEPS[ch] then
				if #cur > 0 then
					T[table.concat(cur)] = true
					cur = {}
				end
			else
				cur[#cur + 1] = ch
			end
		end
		if #cur > 0 then
			T[table.concat(cur)] = true
		end
	end

	return {
		D = D,
		T = T,
		fixed = s6_unique_zh,
		counts = {
			S1 = s1_count,
			S2 = s2_count,
			S3 = s3_count,
			S4 = s4_count,
			S4_per_dlc = s4_per_dlc,
			S5 = s5_count,
			S6 = s6_count,
			S6_en = s6_en_count,
			S6_defs = s6_def_count,
			S6_core_defs = s6_core_defs,
			S6_dlc_defs = s6_dlc_defs,
		},
	}
end

function M.compute_approved_chars(rules)
	local approved = {}
	for _, c in pairs(rules.cultures or {}) do
		local g = c.given or {}
		local s = c.surname or {}
		local lists = { g.initials, g.middles, s.initials, s.middles, s.finals }
		if type(g.finals) == "table" then
			for _, flist in pairs(g.finals) do
				lists[#lists + 1] = flist
			end
		end
		for _, lst in ipairs(lists) do
			if type(lst) == "table" then
				for _, ch in ipairs(lst) do
					approved[ch] = true
				end
			end
		end
	end
	return approved
end

function M.build_collision_tables(rules, sources)
	sources = sources or M.collect_sources()
	local approved = M.compute_approved_chars(rules)
	local D, T = sources.D, sources.T

	-- fixed_name_tokens = { t in T | len(t) >= 3 and all chars in approved }
	local fixed_tokens = {}
	for t in pairs(T) do
		local chars = utf8_chars(t)
		if #chars >= 3 then
			local ok = true
			for _, ch in ipairs(chars) do
				if not approved[ch] then
					ok = false
					break
				end
			end
			if ok then
				fixed_tokens[#fixed_tokens + 1] = t
			end
		end
	end
	table.sort(fixed_tokens)

	-- excluded_exact includes:
	-- 1) { t in T U D | 2 <= len <= 7 and all chars in approved U {separator} } (R1)
	-- 2) 3-char substrings of any t in T (with len(t) >= 4) where all 3 chars are in approved (R3)
	-- 3) Any full entity name d in D that contains at least 2 consecutive approved chars (so prefix .. personal .. suffix can never collide with d in D)
	local sep = rules.separator or "·"
	local excluded_map = {}
	local union_DT = {}
	for k in pairs(D) do union_DT[k] = true end
	for k in pairs(T) do union_DT[k] = true end

	for t in pairs(union_DT) do
		local chars = utf8_chars(t)
		if #chars >= 2 and #chars <= 7 then
			local ok = true
			for _, ch in ipairs(chars) do
				if not approved[ch] and ch ~= sep then
					ok = false
					break
				end
			end
			if ok then
				excluded_map[t] = true
			end
		end
	end

	for t in pairs(T) do
		local chars = utf8_chars(t)
		if #chars >= 4 then
			for i = 1, #chars - 2 do
				local a, b, c = chars[i], chars[i + 1], chars[i + 2]
				if approved[a] and approved[b] and approved[c] then
					excluded_map[a .. b .. c] = true
				end
			end
		end
	end

	-- Full-name R1 defense: bake every d in D that has any 2 consecutive approved_chars
	-- (since every generated personal name contains at least 2 consecutive approved_chars, any d in D without 2 consecutive approved_chars can never equal prefix .. personal .. suffix)
	for d in pairs(D) do
		if not d:find("[#~&%%%c<>]") then
			local chars = utf8_chars(d)
			if #chars >= 2 then
				for i = 1, #chars - 1 do
					if approved[chars[i]] and approved[chars[i + 1]] then
						excluded_map[d] = true
						break
					end
				end
			end
		end
	end

	local excluded_list = {}
	for k in pairs(excluded_map) do
		excluded_list[#excluded_list + 1] = k
	end
	table.sort(excluded_list)

	return {
		approved_chars = approved,
		fixed_name_tokens = fixed_tokens,
		excluded_exact = excluded_map,
		excluded_list = excluded_list,
		sources = sources,
	}
end

if arg and arg[0] and arg[0]:find("gen_randboss_collision_tokens%.lua$") then
	local rules = dofile("data/chn_randboss_names.lua")
	local res = M.build_collision_tables(rules)
	local app_list = {}
	for ch in pairs(res.approved_chars) do app_list[#app_list + 1] = ch end
	table.sort(app_list)

	io.write(string.format("\t-- Source counts: S1=%d S2=%d S3=%d S4=%d S5=%d S6=%d (defs=%d, en=%d)\n",
		res.sources.counts.S1, res.sources.counts.S2, res.sources.counts.S3,
		res.sources.counts.S4, res.sources.counts.S5, res.sources.counts.S6,
		res.sources.counts.S6_defs, res.sources.counts.S6_en))

	io.write("\tapproved_chars = {\n\t\t")
	for i, ch in ipairs(app_list) do
		io.write(string.format("[%q] = true, ", ch))
		if i % 8 == 0 and i < #app_list then io.write("\n\t\t") end
	end
	io.write("\n\t},\n")

	io.write("\tfixed_name_tokens = {\n\t\t")
	for i, tok in ipairs(res.fixed_name_tokens) do
		io.write(string.format("%q, ", tok))
		if i % 6 == 0 and i < #res.fixed_name_tokens then io.write("\n\t\t") end
	end
	io.write("\n\t},\n")

	io.write("\texcluded_exact = {\n\t\t")
	for i, ex in ipairs(res.excluded_list) do
		io.write(string.format("[%q] = true, ", ex))
		if i % 6 == 0 and i < #res.excluded_list then io.write("\n\t\t") end
	end
	io.write("\n\t},\n")
end

return M
