-- Run from the addon root with Lua 5.1 or LuaJIT.
-- Optional arg: extracted 1.7.6 mod/class/Object.lua to exercise its actual getName.
local real_dofile = dofile
dofile = function(path)
    if path == "/data-chn-mod/chn_random_names.lua" then path = "data/chn_random_names.lua" end
    if path == "/hooks/chn-mod/random_artifact_names.lua" then path = "hooks/random_artifact_names.lua" end
    return real_dofile(path)
end
config = { settings = { locale = "zh_hans" } }
local damage_types = {FIRE = 1, COLD = 2, LIGHTNING = 3, LIGHT = 4, DARKNESS = 5}
package.loaded["engine.DamageType"] = damage_types
local original_random = math.random
math.random = function() error("naming used math.random") end
rng = setmetatable({}, {__index = function() error("naming used the engine RNG") end})
local names = dofile("/hooks/chn-mod/random_artifact_names.lua")
local rules = dofile("/data-chn-mod/chn_random_names.lua")
local count, known = 0, {}
for kind, pool in pairs(rules.pools) do
    for _, name in ipairs(pool) do
        assert(not known[name], "duplicate name: " .. name)
        known[name], count = kind, count + 1
    end
end
assert(count >= 40)

local calls = 0
local state = { generateRandart = function(_, o, a, b)
    calls = calls + 1
    if a == "error" then error("stock generation error") end
    return o, a, b
end }
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

if arg and arg[1] then
    local f = assert(io.open(arg[1], "rb"))
    local s = f:read("*a")
    f:close()
    local first = assert(s:find("function _M:getName(t)", 1, true))
    local last = assert(s:find("\n--- Gets the short name", first, true))
    assert(loadstring("local _M = ...\n" .. s:sub(first, last - 1)))(Object)
else
    -- Mirrors the stock presentation paths required by these assertions.
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
    local o = { name = "Iron sword of mischance", define_as = "SWORD_TEST",
        unique = "Test sword", namescheme = "test", randart = true, identified = true,
        type = "weapon", subtype = "longsword" }
    for k,v in pairs(extra or {}) do o[k] = v end
    return setmetatable(o, {__index = Object})
end
local o = artifact{inc_damage = {[1] = 20}, add_name = " (#COMBAT#)", qty = 2, been_reshaped = "重塑"}
local result, hole, tail = state:generateRandart(o, nil, "stock tail")
assert(calls == 1 and result == o and hole == nil and tail == "stock tail")
assert(o.name == "Iron sword of mischance" and o.define_as == "SWORD_TEST"
    and o.unique == "Test sword" and o.namescheme == "test")
local meta = assert(o.__chn_randart_name)
assert(meta.version == 1 and known[meta.text:match("「(.+)」")] == "fire")
local output, blank, third = o:getName{do_color = true}
assert(output == "#FFD700#2 !重塑" .. meta.text .. "（数值）#LAST#" and blank == nil and third == "third")
assert(stock_getName_count == 1 and o.add_name == " (#COMBAT#)")
assert(o:getName{raw_name = true} == o.name)
assert(o:getName{trans_only = true} == "倒霉的铁剑")
assert(o:getName{no_add_name = true, no_count = true} == meta.text)
o.identified = false
assert(not o:getName{force_id = true}:find(meta.text, 1, true))
assert(o:getName{no_count = true} == "未鉴定长剑")
o.identified = true
config.settings.locale = "en_US"
assert(not o:getName():find(meta.text, 1, true))
config.settings.locale = "zh_hans"
assert(o:getName():find(meta.text, 1, true))
assert(not pcall(o.getName, o, {fail = true}) and o.add_name == " (#COMBAT#)")
assert(not pcall(state.generateRandart, state, nil, "error"))
assert(state:generateRandart(nil) == nil)

-- Clone equivalent to a saved/reloaded plain entity; no generator call.
local loaded = artifact()
loaded.__chn_randart_name = {}
for k, v in pairs(meta) do
    assert(type(v) == "string" or type(v) == "number")
    loaded.__chn_randart_name[k] = v
end
assert(loaded:getName() == meta.text)
loaded.unique = "changed identity"
assert(loaded:getName() == "倒霉的铁剑")
assert(artifact():getName() == "倒霉的铁剑")
assert(not state:generateRandart(artifact{randart = false}).__chn_randart_name)
assert(not state:generateRandart(artifact{subtype = "mod-unknown"}).__chn_randart_name)
local mixed = state:generateRandart(artifact{inc_damage = {[1] = 20, [2] = 10}})
assert(known[mixed.__chn_randart_name.text:match("「(.+)」")] == "neutral")
local same = state:generateRandart(artifact{inc_damage = {[1] = 20}})
assert(same.__chn_randart_name.text == meta.text)
assert(names.decorate(o, {}, "倒霉的铁剑和倒霉的铁剑") == "倒霉的铁剑和倒霉的铁剑")
math.random = original_random
print("random artifact naming tests passed (" .. count .. " curated titles)")
