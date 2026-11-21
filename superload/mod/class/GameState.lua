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
        pcall(Names.annotate, result[1], DamageType)
        return unpack(result, 1, result.n)
    end
end

return _M
