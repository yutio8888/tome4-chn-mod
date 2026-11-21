-- Generate fixed_name_tokens and excluded_exact for data/chn_randboss_names.lua (§5.3).
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

local function load_locale_file(path, D, entity_trans, all_trans)
	local f = io.open(path, "rb")
	if not f then
		error("missing required locale source: " .. tostring(path), 0)
	end
	local content = f:read("*a")
	f:close()
	local count = 0
	local env = setmetatable({
		locale = function() end,
		section = function() end,
		setFlag = function() end,
		forceFontPackage = function() end,
		t = function(src, dst, tag)
			if type(src) == "string" and type(dst) == "string" and dst ~= "" then
				if all_trans[src] == nil then
					all_trans[src] = dst
				end
				if tag == "entity name" then
					if entity_trans[src] == nil then
						entity_trans[src] = dst
					end
					D[dst] = true
					count = count + 1
				end
			end
		end,
	}, { __index = _G })
	local chunk = assert(loadstring(content, path))
	setfenv(chunk, env)
	chunk()
	return count
end

local function list_files(cmd)
	local p = assert(io.popen(cmd, "r"))
	local files = {}
	for line in p:lines() do
		if line ~= "" then
			files[#files + 1] = line
		end
	end
	p:close()
	table.sort(files)
	return files
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

	local s1_count = load_locale_file(s1_path, D, entity_trans, all_trans)
	assert(s1_count > 0, "S1 loaded 0 entity names from " .. tostring(s1_path))

	local s2_count = load_locale_file(s2_path, D, entity_trans, all_trans)

	local s3_count = load_locale_file(s3_path, D, entity_trans, all_trans)
	assert(s3_count > 0, "S3 loaded 0 entity names from " .. tostring(s3_path))

	local dlc_paths = {}
	if dlc_zh_env and dlc_zh_env ~= "" then
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
	assert(#dlc_paths >= 3, "S4 requires all 3 DLC locale files")
	local s4_count = 0
	for _, p in ipairs(dlc_paths) do
		local c = load_locale_file(p, D, entity_trans, all_trans)
		assert(c > 0, "S4 loaded 0 entity names from " .. tostring(p))
		s4_count = s4_count + c
	end

	-- S5: terminology/*.tsv
	local tsv_files = list_files(string.format("find %q -maxdepth 1 -name '*.tsv' 2>/dev/null", term_dir))
	assert(#tsv_files > 0, "S5 found no .tsv files in " .. tostring(term_dir))
	local s5_count = 0
	for _, tsv in ipairs(tsv_files) do
		local f = assert(io.open(tsv, "rb"))
		local first_line = true
		for line in f:lines() do
			line = line:gsub("\r$", "")
			if not first_line then
				local cols = {}
				for col in (line .. "\t"):gmatch("([^\t]*)\t") do
					cols[#cols + 1] = col
				end
				local target, cat = cols[2], cols[3]
				if TERM_CATS[cat] and type(target) == "string" and target ~= "" then
					D[target] = true
					s5_count = s5_count + 1
				end
			end
			first_line = false
		end
		f:close()
	end
	assert(s5_count > 0, "S5 loaded 0 terminology entries from " .. tostring(term_dir))

	-- S6: fixed unique entities from TOME_DATA_DIR and DLC_ROOT
	local lua_files = list_files(string.format("find %q %q -name '*.lua' ! -path '*/locales/*' 2>/dev/null", tome_data_dir, dlc_root))
	assert(#lua_files > 0, "S6 found no lua files in data dirs")
	local s6_unique_zh = {}
	local s6_en_count = 0
	for _, lf in ipairs(lua_files) do
		local f = io.open(lf, "rb")
		if f then
			local s = f:read("*a")
			f:close()
			if s:find("newEntity", 1, true) and s:find("unique", 1, true) then
				local pos = 1
				while true do
					local start = s:find("newEntity", pos, true)
					if not start then break end
					local next_start = s:find("newEntity", start + 9, true)
					local block = s:sub(start, (next_start or (#s + 1)) - 1)
					if block:match("unique%s*=%s*true") or block:match("unique%s*=%s*\"[^\"]+\"") then
						for name in block:gmatch("name%s*=%s*_?t?%s*\"([^\"]+)\"") do
							s6_en_count = s6_en_count + 1
							local zh = entity_trans[name] or all_trans[name]
							if zh and zh ~= "" then
								D[zh] = true
								s6_unique_zh[zh] = true
							end
						end
					end
					if not next_start then break end
					pos = next_start
				end
			end
		end
	end
	local s6_count = 0
	for _ in pairs(s6_unique_zh) do s6_count = s6_count + 1 end
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
		counts = {
			S1 = s1_count,
			S2 = s2_count,
			S3 = s3_count,
			S4 = s4_count,
			S5 = s5_count,
			S6 = s6_count,
			S6_en = s6_en_count,
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

	io.write(string.format("-- Source counts: S1=%d S2=%d S3=%d S4=%d S5=%d S6=%d\n",
		res.sources.counts.S1, res.sources.counts.S2, res.sources.counts.S3,
		res.sources.counts.S4, res.sources.counts.S5, res.sources.counts.S6))

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
