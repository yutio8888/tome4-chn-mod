local rules = dofile("/data-chn-mod/chn_random_names.lua")
local M = {
	rules = rules,
	MAX_LEDGER = 8192,
	PROBE_STRIDE = 2971,
}

local function zh()
	return config and config.settings and config.settings.locale == "zh_hans"
end

local function plain_label(s)
	-- Reject engine name/color markup and control bytes rather than trying to re-create getName.
	return type(s) == "string" and #s > 0 and not s:find("[#~&%%%c<>]")
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

local function valid_core_chars(prefix, noun, conn)
	local p_chars = utf8_chars(prefix)
	local n_chars = utf8_chars(noun)
	if #p_chars < 2 or #n_chars < 1 then
		return false
	end
	-- Avoid 5+ char unseparated compounds (3+2, 2+3, 3+3 with empty connector);
	-- 3-char phrases pair naturally with "之" or "的" to form rhythmic 5-7 char titles.
	if conn == "" and (#p_chars > 2 or #n_chars > 2) then
		return false
	end
	local seen = {}
	for i = 1, #p_chars do
		local c = p_chars[i]
		if seen[c] then
			return false
		end
		seen[c] = true
	end
	for i = 1, #n_chars do
		local c = n_chars[i]
		if seen[c] then
			return false
		end
		seen[c] = true
	end
	return true
end

local function theme(obj, damage_types)
	local found
	local inc = type(obj.wielder) == "table" and obj.wielder.inc_damage
	inc = type(inc) == "table" and inc or nil
	local combat = type(obj.combat) == "table" and obj.combat or nil
	local dts = type(damage_types) == "table" and damage_types or package.loaded["engine.DamageType"]
	for _, kind in ipairs{"FIRE", "COLD", "LIGHTNING", "LIGHT", "DARKNESS"} do
		local id = type(dts) == "table" and dts[kind] or kind
		local bonus = id and inc and inc[id]
		if id and (type(bonus) == "number" and bonus > 0
			or combat and (combat.element == id or combat.damtype == id)) then
			if found then return "neutral" end
			found = kind:lower()
		end
	end
	return found or "neutral"
end

local function base_and_family(obj)
	if type(obj) ~= "table" then
		return nil, nil
	end
	local by_type = type(rules.base_names) == "table" and rules.base_names[obj.type]
	local base = by_type and by_type[obj.subtype]
	local fam_by_type = type(rules.families) == "table" and rules.families[obj.type]
	local family = fam_by_type and fam_by_type[obj.subtype]
	if not base or not family then
		return nil, nil
	end
	return base, family
end

local function hash31(key)
	-- Small integer arithmetic, exact under the Lua 5.1 number model.
	local h = 0
	for i = 1, #key do
		h = (h * 131 + key:byte(i)) % 2147483647
	end
	return h
end

local function seed_key(obj, pool_name, family_name)
	return table.concat({
		tostring(rules.version or 2),
		tostring(pool_name or "neutral"),
		tostring(family_name or "blade"),
		tostring(obj.type or ""),
		tostring(obj.subtype or ""),
		tostring(obj.unique or ""),
		tostring(obj.define_as or ""),
	}, "\0")
end

local function active_state(explicit_state)
	if type(explicit_state) == "table" then
		return explicit_state
	end
	local g = rawget(_G, "game")
	if type(g) == "table" and type(g.state) == "table" then
		return g.state
	end
	return nil
end

local function ensure_ledger(state)
	if type(state) ~= "table" then
		return nil
	end
	local raw = rawget(state, "__chn_randart_ledger")
	if raw == nil then
		local fresh = {
			version = 2,
			count = 0,
			used = {},
		}
		rawset(state, "__chn_randart_ledger", fresh)
		return fresh
	end
	if type(raw) ~= "table"
		or raw.version ~= 2
		or type(raw.used) ~= "table"
		or type(raw.count) ~= "number"
		or raw.count < 0
		or raw.count > M.MAX_LEDGER
		or math.floor(raw.count) ~= raw.count
	then
		return nil
	end
	return raw
end

local function cohort_dimensions(pool_name, family_name)
	local prefixes = type(rules.prefixes) == "table" and rules.prefixes[pool_name] or nil
	local nouns_2 = type(rules.nouns_2) == "table" and rules.nouns_2[family_name] or nil
	local nouns_1 = type(rules.nouns_1) == "table" and rules.nouns_1[family_name] or nil
	local connectors = type(rules.connectors) == "table" and rules.connectors or nil
	local single_conn = type(rules.single_connector) == "string" and rules.single_connector or "之"
	if type(prefixes) ~= "table" or #prefixes == 0 then
		return nil
	end
	if type(nouns_2) ~= "table" or #nouns_2 == 0 then
		return nil
	end
	if type(connectors) ~= "table" or #connectors == 0 then
		return nil
	end
	local n1_count = type(nouns_1) == "table" and #nouns_1 or 0
	local n2_slots = #nouns_2 * #connectors
	local per_prefix = n2_slots + n1_count
	local total = #prefixes * per_prefix
	return prefixes, nouns_2, nouns_1, connectors, single_conn, n2_slots, per_prefix, total
end

local function candidate_at(pool_name, family_name, idx)
	local prefixes, nouns_2, nouns_1, connectors, single_conn, n2_slots, per_prefix, total = cohort_dimensions(pool_name, family_name)
	if not prefixes or total <= 0 then
		return nil
	end
	local norm = idx % total
	local p_idx = math.floor(norm / per_prefix) + 1
	local rem = norm % per_prefix
	local prefix = prefixes[p_idx]
	if not plain_label(prefix) then
		return nil
	end
	local noun, conn
	if rem < n2_slots then
		local n_idx = math.floor(rem / #connectors) + 1
		local c_idx = (rem % #connectors) + 1
		noun = nouns_2[n_idx]
		conn = connectors[c_idx]
	else
		local n1_idx = (rem - n2_slots) + 1
		noun = nouns_1 and nouns_1[n1_idx] or nil
		conn = single_conn
	end
	if not plain_label(noun) or type(conn) ~= "string" then
		return nil
	end
	if not valid_core_chars(prefix, noun, conn) then
		return nil
	end
	local title = prefix .. conn .. noun
	if not plain_label(title) then
		return nil
	end
	if type(rules.excluded_titles) == "table" and rules.excluded_titles[title] then
		return nil
	end
	return title, prefix .. noun
end

local function select_v2_name(base, pool_name, family_name, key, ledger)
	if type(ledger) == "table" and ledger.count >= M.MAX_LEDGER then
		return nil
	end
	local _, _, _, _, _, _, _, total = cohort_dimensions(pool_name, family_name)
	if not total or total <= 0 then
		return nil
	end
	local start = hash31(key) % total
	local used = type(ledger) == "table" and ledger.used or nil
	for step = 0, total - 1 do
		local idx = (start + step * M.PROBE_STRIDE) % total
		local title = candidate_at(pool_name, family_name, idx)
		if title then
			local full = base .. "「" .. title .. "」"
			if not used or not used[full] then
				return full
			end
		end
	end
	return nil
end

local function pick_available_v2(base, pool, family, obj, ledger)
	local key = seed_key(obj, pool, family)
	local full = select_v2_name(base, pool, family, key, ledger)
	if full then
		return full, pool
	end
	if pool ~= "neutral" then
		local nkey = seed_key(obj, "neutral", family)
		full = select_v2_name(base, "neutral", family, nkey, ledger)
		if full then
			return full, "neutral"
		end
	end
	return nil, nil
end

function M.audit_cohort(pool_name, family_name, base_label)
	local base = plain_label(base_label) and base_label or "长剑"
	local _, _, _, _, _, _, _, total = cohort_dimensions(pool_name, family_name)
	if not total or total <= 0 then
		return {
			raw_slots = 0,
			normalized_count = 0,
			core_count = 0,
			list = {},
		}
	end
	local seen_full = {}
	local seen_core = {}
	local list = {}
	local core_count = 0
	for idx = 0, total - 1 do
		local title, core = candidate_at(pool_name, family_name, idx)
		if title then
			local full = base .. "「" .. title .. "」"
			if not seen_full[full] then
				seen_full[full] = true
				list[#list + 1] = full
			end
			if core and not seen_core[core] then
				seen_core[core] = true
				core_count = core_count + 1
			end
		end
	end
	return {
		raw_slots = total,
		normalized_count = #list,
		core_count = core_count,
		list = list,
	}
end

function M.enumerate_cohort(pool_name, family_name, base_label)
	local res = M.audit_cohort(pool_name, family_name, base_label)
	return res.list, res.raw_slots, res.core_count
end

function M.annotate(obj, damage_types, state)
	if type(obj) ~= "table" or obj.randart ~= true or rawget(obj, "__chn_randart_name")
		or not plain_label(obj.name) or type(obj.unique) ~= "string" or obj.unique == ""
		or type(obj.define_as) ~= "string" or obj.define_as == "" then return end
	local base, family = base_and_family(obj)
	if not base or not family then return end
	local pool = theme(obj, damage_types)
	local st = active_state(state)
	local ledger = st and ensure_ledger(st) or nil
	local full, actual_pool = pick_available_v2(base, pool, family, obj, ledger)
	-- Name/unique also guard against metadata copied by addRandartProperties and other postprocessors.
	rawset(obj, "__chn_randart_name", {
		version = rules.version,
		issued = false,
		text = full or "",
		pool = actual_pool or pool,
		family = family,
		original = obj.name,
		unique = obj.unique,
		define_as = obj.define_as,
	})
end

function M.is_enabled()
	local s = type(config) == "table" and config.settings or nil
	local cm = type(s) == "table" and s.chn_mod or nil
	if type(cm) == "table" and cm.randart_names == false then
		return false
	end
	return true
end

function M.decorate(obj, opts, rendered, state)
	if not zh() or not M.is_enabled() or type(obj) ~= "table" or obj.randart ~= true or type(rendered) ~= "string"
		or opts and (type(opts) ~= "table" or opts.raw_name or opts.trans_only)
		or type(obj.isIdentified) ~= "function" or not obj:isIdentified() then return rendered end
	local meta = rawget(obj, "__chn_randart_name")
	if type(meta) ~= "table" or (meta.version ~= 1 and meta.version ~= 2)
		or meta.original ~= obj.name or meta.unique ~= obj.unique
		or meta.define_as ~= obj.define_as or not plain_label(obj.name) then return rendered end

	local original = type(_G._t) == "function" and _G._t(obj.name, "entity name") or obj.name
	if not plain_label(original) then return rendered end
	local first, last = rendered:find(original, 1, true)
	-- In an ambiguous/custom rendering, the safest behavior is to keep the original.
	if not first or rendered:find(original, first + 1, true) then return rendered end

	local base, family = base_and_family(obj)
	if meta.version == 2 then
		if not base or not family then return rendered end
		local st = active_state(state)
		local ledger = st and ensure_ledger(st) or nil
		if meta.issued == true then
			if not plain_label(meta.text) then return rendered end
			if ledger and not ledger.used[meta.text] and ledger.count < M.MAX_LEDGER then
				ledger.used[meta.text] = true
				ledger.count = ledger.count + 1
			end
		else
			if not ledger or ledger.count >= M.MAX_LEDGER then
				return rendered
			end
			local chosen_text = meta.text
			local chosen_pool = meta.pool or theme(obj)
			local chosen_family = meta.family or family
			if not plain_label(chosen_text) or ledger.used[chosen_text] then
				chosen_text, chosen_pool = pick_available_v2(base, chosen_pool, chosen_family, obj, ledger)
				if not plain_label(chosen_text) then
					return rendered
				end
			end
			ledger.used[chosen_text] = true
			ledger.count = ledger.count + 1
			meta.text = chosen_text
			meta.pool = chosen_pool
			meta.family = chosen_family
			meta.issued = true
		end
	else
		if not plain_label(meta.text) then return rendered end
	end

	return rendered:sub(1, first - 1) .. meta.text .. rendered:sub(last + 1)
end

return M
