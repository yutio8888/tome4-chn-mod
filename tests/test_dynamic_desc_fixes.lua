-- Regression test for hooks/dynamic_desc_fixes.lua (LuaJIT / Lua 5.1).
--
-- Uses the real upstream definitions and engine code instead of mirrors:
--   CHN_TEST_ENTITY      engine/Entity.lua at the pinned core commit
--                        (addTemporaryValue / removeTemporaryValue are loaded from it)
--   CHN_TEST_ORCS_ROOT   tome-orcs addon source root (data/talents/steam/sawmaiming.lua,
--                        data/timed_effects/other.lua)
--   CHN_TEST_LOCALE      Chinese translation file containing the Embers strings
--                        (new locale; data/chn_supplement.lua of this tree is added)
--   CHN_TEST_OLD_LOCALE  optional: data/locales/zh_hans.lua of the previous release
--                        (old locale, used for the code/locale pairing matrix)
--
-- Run: luajit tests/test_dynamic_desc_fixes.lua   (from the addon root)

local function env(name)
    local v = os.getenv(name)
    if not v or v == "" then error("missing environment variable "..name, 0) end
    return v
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function check(cond, label)
    if not cond then error("FAIL: "..label, 2) end
    print("ok   "..label)
end

-- deep copy / compare, used to prove that description calls change nothing
local function copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {}
    seen[v] = c
    for k, x in pairs(v) do c[copy(k, seen)] = copy(x, seen) end
    return c
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- ---------------------------------------------------------------- locale
local function load_locale(paths)
    local out = {}
    for _, path in ipairs(paths) do
        local lenv = setmetatable({
            locale = function() end, section = function() end,
            setFlag = function() end, forceFontPackage = function() end,
            t = function(src, dst) if out[src] == nil then out[src] = dst end end,
        }, {__index = _G})
        local chunk = assert(loadstring(read(path), "locale"))
        setfenv(chunk, lenv)
        chunk()
    end
    return out
end

local SUPPLEMENT = "data/chn_supplement.lua"
local locales = {
    new = load_locale({env("CHN_TEST_LOCALE"), SUPPLEMENT}),
    new_nosupp = load_locale({env("CHN_TEST_LOCALE")}),
}
local old_path = os.getenv("CHN_TEST_OLD_LOCALE")
if old_path and old_path ~= "" then
    locales.old = load_locale({old_path, SUPPLEMENT})
    locales.old_nosupp = load_locale({old_path})
end
local tr = locales.new

config = {settings = {locale = "zh_hans"}}
local raw_format = string.format
function _t(s) if config.settings.locale == "zh_hans" and tr[s] then return tr[s] end return s end
function string.tformat(s, ...) return raw_format(_t(s), ...) end

-- ---------------------------------------------------------------- engine temporary values
local Entity
do
    local src = read(env("CHN_TEST_ENTITY"))
    local a = src:find("\nfunction _M:addTemporaryValue", 1, true)
    local r = src:find("\nfunction _M:removeTemporaryValue", 1, true)
    local e = src:find("\nfunction _M:", r + 10, true)
    assert(a and r and e, "temporary value functions not found in Entity.lua")
    local body = "local _M = {temporary_values_conf = {}}\n"..src:sub(a, e).."\nreturn _M"
    local chunk = assert(loadstring(body, "Entity.temporary_values"))
    setfenv(chunk, setmetatable({util = {send_error_backtrace = function(m) error(m) end,
                                         bound = function(v, l, h) return math.max(l, math.min(h, v)) end}},
                                {__index = _G}))
    Entity = chunk()
end

local function new_actor(extra)
    local a = {onTemporaryValueChange = function() end, temporary_values_conf = {},
               life_regen = 1, resists = {all = 5}, die_at = 0}
    a.addTemporaryValue = Entity.addTemporaryValue
    a.removeTemporaryValue = Entity.removeTemporaryValue
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

-- ---------------------------------------------------------------- upstream definitions
local function extract_block(path, opener, name)
    local src = read(path)
    local at = src:find('name = "'..name..'"', 1, true)
    assert(at, name.." not found in "..path)
    local start = 1
    local pos = 1
    while true do
        local s = src:find("\n"..opener.."{", pos, true)
        if not s or s > at then break end
        start, pos = s + 1, s + 1
    end
    local stop = src:find("\n}", at, true)
    return src:sub(start, stop + 2)
end

local orcs = env("CHN_TEST_ORCS_ROOT")
local captured
local function capture(t) captured = t end
local defenv = setmetatable({newTalent = capture, newEffect = capture,
                             DamageType = {PHYSICAL = "PHYSICAL"}}, {__index = _G})

local function load_def(path, opener, name)
    captured = nil
    local chunk = assert(loadstring(extract_block(path, opener, name), name))
    setfenv(chunk, defenv)
    chunk()
    return assert(captured, name.." not captured")
end

local sawmaiming = orcs.."/data/talents/steam/sawmaiming.lua"
local other = orcs.."/data/timed_effects/other.lua"

local M = dofile("hooks/dynamic_desc_fixes.lua")

-- format literals must equal the upstream keys byte for byte
check(read(sawmaiming):find(M.BLOODSTREAM_FMT, 1, true) ~= nil, "Bloodstream format literal equals upstream")
check(read(other):find(M.REPAIR_FMT, 1, true) ~= nil, "Automated repair format literal equals upstream")
check(tr[M.BLOODSTREAM_FMT] ~= nil, "Bloodstream upstream key has a Chinese translation")
check(read(sawmaiming):find(M.BLOODSTREAM_ZH_KEY, 1, true) == nil, "Bloodstream dedicated key is not an upstream string")
check(locales.new[M.BLOODSTREAM_ZH_KEY] ~= nil, "Bloodstream dedicated key translated by data/chn_supplement.lua")
check(locales.new_nosupp[M.BLOODSTREAM_ZH_KEY] == nil, "Bloodstream dedicated key absent from the generated translation")
do
    local function tokens(str)
        local r = {}
        for tok in str:gmatch("%%[%-%d%.]*[%a%%]") do r[#r + 1] = tok end
        return table.concat(r, " ")
    end
    check(tokens(M.BLOODSTREAM_ZH_KEY) == tokens(M.BLOODSTREAM_FMT), "Bloodstream dedicated key keeps the upstream placeholder list")
    check(tokens(locales.new[M.BLOODSTREAM_ZH_KEY]) == tokens(M.BLOODSTREAM_ZH_KEY), "Bloodstream dedicated Chinese keeps the placeholder list")
    -- old argument contract: the upstream key's Chinese must describe getDamageInc as an increase
    for name, loc in pairs(locales) do
        local zh = loc[M.BLOODSTREAM_FMT]
        check(zh and zh:find("伤害增加 %d%%", 1, true) and not zh:find("变为原来的", 1, true),
              "Bloodstream upstream key keeps the old 'increase' contract ("..name..")")
        check(tokens(zh) == tokens(M.BLOODSTREAM_FMT), "Bloodstream upstream Chinese keeps placeholders ("..name..")")
    end
end
check(tr[M.REPAIR_FMT] ~= nil, "Automated repair has a Chinese translation")

-- ---------------------------------------------------------------- Automated Repair System
do
    local def = load_def(other, "newEffect", "AUTOMATED_REPAIR_SYSTEM")
    local orig_long = def.long_desc
    check(M.installAutomatedRepair(def) == true, "repair: installed")
    check(M.installAutomatedRepair(def) == false, "repair: install is idempotent")

    local actor = new_actor()
    -- unrelated temporary values first, so ids differ from the effect values
    local other_ids = {actor:addTemporaryValue("life_regen", 2), actor:addTemporaryValue("resists", {all = 3}),
                       actor:addTemporaryValue("die_at", -4)}
    local eff = {heal = 37, resist = 23, life = 410}
    def.activate(actor, eff)
    check(eff.heal ~= 37 and eff.resist ~= 23 and eff.life ~= 410, "repair: activate replaced fields with ids")

    config.settings.locale = "en_US"
    check(def.long_desc(actor, eff) == orig_long(actor, eff), "repair: English output unchanged (still upstream)")

    config.settings.locale = "zh_hans"
    local before_eff, before_actor = copy(eff), copy(actor)
    local zh = def.long_desc(actor, eff)
    local expected = raw_format(tr[M.REPAIR_FMT], 37, 23, 410)
    check(zh == expected, "repair: Chinese shows 37 / 23% / -410 ("..zh..")")
    check(def.long_desc(actor, eff) == zh, "repair: repeated read is stable")
    check(same(eff, before_eff) and same(actor, before_actor), "repair: eff and actor unchanged by description")

    local later = actor:addTemporaryValue("life_regen", 99)
    check(def.long_desc(actor, eff) == zh, "repair: other temporary values do not change the figures")
    actor:removeTemporaryValue("life_regen", later)

    def.deactivate(actor, eff)
    check(actor.life_regen == 1 + 2 and actor.die_at == -4, "repair: normal removal restores totals")
    local ok = pcall(def.long_desc, actor, eff)
    check(ok, "repair: description after removal falls back without error")
    for _, id in ipairs(other_ids) do check(actor.compute_vals[id] ~= nil, "repair: unrelated value "..id.." intact") end

    local bare = {}
    check(pcall(def.long_desc, new_actor(), {heal = 1, resist = 2, life = 3}), "repair: missing registry falls back")
    check(M.repairIncrements(bare, {}) == nil, "repair: malformed input yields nil")
end

-- ---------------------------------------------------------------- Bloodstream
do
    local def = load_def(sawmaiming, "newTalent", "Bloodstream")
    local orig_info = def.info
    local function damDesc(self, typ, dam) return dam * (self.dam_mult or 1) end
    defenv.damDesc = damDesc
    check(M.installBloodstream(def, damDesc, "PHYSICAL") == true, "bloodstream: installed")
    check(M.installBloodstream(def, damDesc, "PHYSICAL") == false, "bloodstream: install is idempotent")

    local function actor(level, steam)
        return {
            combatTalentSteamDamage = function(self, t, base, max) return base + (max - base) * level / 5 * steam end,
            combatTalentWeaponDamage = function(self, t, base, max) return base + (max - base) * level / 5 end,
            combatTalentLimit = function(self, t, limit, low, high) return low + (high - low) * level / 5 end,
        }
    end
    local function args(a, third)
        return a:combatTalentWeaponDamage(def, 0.3, 1.1) * 100, def.getDuration(a, def), third,
               damDesc(a, "PHYSICAL", def.getDamage(a, def))
    end
    -- what each code version shows with a given locale
    local function new_code(a) return def.info(a, def) end
    local function old_code(a) return orig_info(a, def) end
    local function expect_fixed(loc, a)
        return raw_format(loc[M.BLOODSTREAM_ZH_KEY], args(a, def.getDamage(a, def)))
    end
    local function expect_upstream(loc, a)
        return raw_format(loc[M.BLOODSTREAM_FMT], args(a, def.getDamageInc(a, def)))
    end
    local function no_new_mismatch(out, a, label)
        local inc, mult = def.getDamageInc(a, def), def.getDamage(a, def)
        if out:find("变为原来的", 1, true) then
            check(out:find("变为原来的 "..raw_format("%d", mult).."%", 1, true) ~= nil, label..": multiplier wording carries getDamage")
        else
            check(out:find("伤害增加 "..raw_format("%d", inc).."%", 1, true) ~= nil, label..": increase wording carries getDamageInc (upstream contract)")
        end
    end

    local matrix = {
        {"new code + new locale", "new", new_code, expect_fixed},
        {"new code + new locale without supplement", "new_nosupp", new_code, expect_upstream},
        {"old code + new locale", "new", old_code, expect_upstream},
    }
    if locales.old then
        matrix[#matrix + 1] = {"new code + old locale", "old", new_code, expect_fixed}
        matrix[#matrix + 1] = {"new code + old locale without supplement", "old_nosupp", new_code, expect_upstream}
        matrix[#matrix + 1] = {"old code + old locale", "old_nosupp", old_code, expect_upstream}
    else
        print("skip old-locale pairings: CHN_TEST_OLD_LOCALE not set")
    end

    for _, case in ipairs({{0.2, 0.5}, {1, 1}, {5, 1}, {3, 0.8}}) do
        local a = actor(case[1], case[2])
        local tag = ("L%.1f/S%.1f"):format(case[1], case[2])
        config.settings.locale = "en_US"
        check(new_code(a) == old_code(a), "bloodstream "..tag..": English byte-identical to upstream info")
        config.settings.locale = "zh_hans"
        for _, m in ipairs(matrix) do
            tr = locales[m[2]]
            local before = copy(a)
            local out = m[3](a)
            check(out == m[4](tr, a), "bloodstream "..tag..": "..m[1])
            no_new_mismatch(out, a, "bloodstream "..tag..": "..m[1])
            check(same(a, before), "bloodstream "..tag..": "..m[1]..": actor unchanged")
        end
        tr = locales.new

        -- injected error inside the new path: back to the original info (old contract)
        local saved = string.tformat
        string.tformat = function(fmt, ...) if fmt == M.BLOODSTREAM_ZH_KEY then error("injected") end return saved(fmt, ...) end
        local before = copy(a)
        local ok, out = pcall(new_code, a)
        string.tformat = saved
        check(ok and out == expect_upstream(tr, a), "bloodstream "..tag..": injected error falls back to original info")
        no_new_mismatch(out, a, "bloodstream "..tag..": injected error")
        check(same(a, before), "bloodstream "..tag..": injected error leaves the actor unchanged")
    end
    local low = actor(0.2, 0.5)
    check(def.getDamage(low, def) < 100, "bloodstream: covered a multiplier below 100%")
    check(M.installBloodstream(nil, damDesc, "PHYSICAL") == false, "bloodstream: missing definition is a no-op")
    local saved_t = _t
    _t = nil
    check(M.hasTranslation(M.BLOODSTREAM_ZH_KEY, "tformat") == false, "bloodstream: no _t means no new path")
    _t = saved_t
end

-- ---------------------------------------------------------------- integration / fallback
do
    -- install() with no DLC definitions loaded: must be a no-op without error
    package.loaded["engine.interface.ActorTalents"] = {talents_def = {}, damDesc = function(_, _, d) return d end}
    package.loaded["engine.interface.ActorTemporaryEffects"] = {tempeffect_def = {}}
    package.loaded["engine.DamageType"] = {PHYSICAL = "PHYSICAL"}
    check(pcall(M.install), "install: no DLC definitions is a no-op")

    -- production chain: real i18nhelper:replaceFormat as the inner wrapper, then install() on top
    local helper = dofile("overload/engine/i18nhelper.lua")
    local def = load_def(other, "newEffect", "AUTOMATED_REPAIR_SYSTEM")
    local upstream = def.long_desc
    def.long_desc = helper:replaceFormat(def.long_desc)
    local inner = def.long_desc
    package.loaded["engine.interface.ActorTemporaryEffects"] = {tempeffect_def = {EFF_AUTOMATED_REPAIR_SYSTEM = def}}
    M.install()
    local a = new_actor()
    a:addTemporaryValue("life_regen", 8)
    local eff = {heal = 12, resist = 34, life = 56}
    def.activate(a, eff)
    config.settings.locale = "en_US"
    check(def.long_desc(a, eff) == inner(a, eff) and def.long_desc(a, eff) == upstream(a, eff), "chain: English equals the replaceFormat-wrapped upstream output")
    config.settings.locale = "zh_hans"
    check(def.long_desc(a, eff) == raw_format(tr[M.REPAIR_FMT], 12, 34, 56), "chain: Chinese shows 12 / 34% / -56 through the production chain")

    -- injected formatting error: falls back to the wrapped original, state unchanged
    local saved = string.tformat
    local snapshot = copy(a)
    string.tformat = function(fmt, ...) if fmt == M.REPAIR_FMT then error("injected") end return saved(fmt, ...) end
    local ok, res = pcall(def.long_desc, a, eff)
    string.tformat = saved
    check(not ok or res ~= raw_format(tr[M.REPAIR_FMT], 12, 34, 56), "chain: injected tformat error does not claim the fixed figures")
    check(same(a, snapshot), "chain: injected error leaves the actor unchanged")

    -- removal clears exactly the three slots and restores totals
    local ids = {eff.heal, eff.resist, eff.life}
    def.deactivate(a, eff)
    check(a.compute_vals[ids[1]] == nil and a.compute_vals[ids[2]] == nil and a.compute_vals[ids[3]] == nil, "chain: removal empties the three registry slots")
    check(a.life_regen == 1 + 8 and a.resists.all == 5 and a.die_at == 0, "chain: removal restores life_regen, resists.all and die_at")
end

print("ALL OK")
