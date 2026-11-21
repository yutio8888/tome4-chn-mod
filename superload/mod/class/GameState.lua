local _M = loadPrevious(...)
local Names = dofile("/hooks/chn-mod/random_artifact_names.lua")
local DamageType = require "engine.DamageType"
local function pack(...) return {n = select("#", ...), ...} end

if not rawget(_M, "__chn_generateRandart") and type(_M.generateRandart) == "function" then
    _M.__chn_generateRandart = true
    local generate = _M.generateRandart
    function _M:generateRandart(...)
        local result = pack(generate(self, ...))
        -- Upstream remains authoritative and errors from the original generator propagate.
        pcall(Names.annotate, result[1], DamageType, self)
        return unpack(result, 1, result.n)
    end
end

local ok_boss, BossNames = pcall(dofile, "/hooks/chn-mod/random_boss_names.lua")
if not ok_boss then BossNames = dofile("hooks/random_boss_names.lua") end

for _, fname in ipairs{"createRandomBoss", "createRandomBossNew"} do
    local sentinel = "__chn_" .. fname
    if not rawget(_M, sentinel) and type(_M[fname]) == "function" then
        _M[sentinel] = true
        local orig = _M[fname]
        _M[fname] = function(self, base, data, ...)
            local result = pack(orig(self, base, data, ...))
            pcall(BossNames.rename, result[1], base, data, self)
            return unpack(result, 1, result.n)
        end
    end
end

return _M
