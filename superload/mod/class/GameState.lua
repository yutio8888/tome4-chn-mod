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

local function is_zh_hans()
    return config and config.settings and config.settings.locale == "zh_hans"
end

for _, fname in ipairs{"createRandomBoss", "createRandomBossNew"} do
    local sentinel = "__chn_" .. fname
    if not rawget(_M, sentinel) and type(_M[fname]) == "function" then
        _M[sentinel] = true
        local orig = _M[fname]
        _M[fname] = function(self, base, data, ...)
            if not is_zh_hans() then
                return orig(self, base, data, ...)
            end
            local call_data = data
            local post_changed = false
            if type(data) == "table" then
                call_data = setmetatable({}, {
                    __newindex = data,
                    __index = function(_, k)
                        if k == "init" then
                            local real_init = data.init
                            if not real_init then return real_init end
                            return function(_p, boss, ...)
                                return real_init(data, boss, ...)
                            end
                        elseif k == "post" then
                            local real_post = data.post
                            if not real_post then return real_post end
                            return function(boss, _p, ...)
                                local pre_name = type(boss) == "table" and boss.name or nil
                                local pre_unique = type(boss) == "table" and boss.unique or nil
                                local res = pack(real_post(boss, data, ...))
                                if type(boss) == "table" and (boss.name ~= pre_name or boss.unique ~= pre_unique) then
                                    post_changed = true
                                end
                                return unpack(res, 1, res.n)
                            end
                        end
                        return data[k]
                    end,
                })
            end
            local result = pack(orig(self, base, call_data, ...))
            if not post_changed then
                pcall(BossNames.rename, result[1], base, data, self)
            end
            return unpack(result, 1, result.n)
        end
    end
end

return _M
