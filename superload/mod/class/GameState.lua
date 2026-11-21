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
            local orig_post = type(data) == "table" and rawget(data, "post") or nil
            local pre_name, pre_unique, post_called = nil, nil, false
            local wrapped_post = nil
            if type(orig_post) == "function" then
                wrapped_post = function(b, d, ...)
                    if not post_called and type(b) == "table" then
                        post_called = true
                        pre_name = rawget(b, "name")
                        pre_unique = rawget(b, "unique")
                    end
                    rawset(data, "post", orig_post)
                    return orig_post(b, d, ...)
                end
                rawset(data, "post", wrapped_post)
            end
            local ok, result = pcall(function(...)
                return pack(orig(self, base, data, ...))
            end, ...)
            if wrapped_post and type(data) == "table" and rawget(data, "post") == wrapped_post then
                rawset(data, "post", orig_post)
            end
            if not ok then
                error(result, 0)
            end
            local b = result[1]
            local post_modified = post_called and type(b) == "table" and (rawget(b, "name") ~= pre_name or rawget(b, "unique") ~= pre_unique)
            if not post_modified then
                pcall(BossNames.rename, b, base, data, self)
            end
            return unpack(result, 1, result.n)
        end
    end
end

return _M
