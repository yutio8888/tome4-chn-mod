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
        local wrap_rnd_boss_init = (fname == "createRandomBoss")
        _M[fname] = function(self, base, data, ...)
            if not is_zh_hans() then
                return orig(self, base, data, ...)
            end
            local call_base = base
            local call_data = data
            local post_changed = false
            local rbi_state = nil

            local function restore_rbi()
                if rbi_state and rawget(rbi_state.b, "rnd_boss_init") == rbi_state.wrapper then
                    rawset(rbi_state.b, "rnd_boss_init", rbi_state.raw)
                end
                rbi_state = nil
            end

            local function install_rbi(b)
                if not wrap_rnd_boss_init or type(b) ~= "table" then return end
                if rbi_state and rbi_state.b == b and rawget(b, "rnd_boss_init") == rbi_state.wrapper then
                    return
                end
                restore_rbi()
                local real_rbi = b.rnd_boss_init
                if not real_rbi then return end
                local raw_rbi = rawget(b, "rnd_boss_init")
                local wrapper
                wrapper = function(boss, arg2, ...)
                    restore_rbi()
                    if rawequal(arg2, call_data) then
                        arg2 = data
                    end
                    return real_rbi(boss, arg2, ...)
                end
                rbi_state = { b = b, raw = raw_rbi, wrapper = wrapper }
                rawset(b, "rnd_boss_init", wrapper)
            end

            if type(data) == "table" then
                if wrap_rnd_boss_init and type(base) == "table" and type(base.clone) == "function" then
                    local clone_count = 0
                    call_base = setmetatable({
                        clone = function(_bp, ...)
                            clone_count = clone_count + 1
                            local b = base:clone(...)
                            if clone_count == 1 then
                                install_rbi(b)
                            end
                            return b
                        end,
                    }, { __index = base, __newindex = base })
                end
                call_data = setmetatable({}, {
                    __newindex = function(_, k, v)
                        local ok, err = pcall(function() data[k] = v end)
                        if not ok then
                            restore_rbi()
                            error(err, 0)
                        end
                    end,
                    __index = function(_, k)
                        if k == "init" then
                            local real_init = data.init
                            if not real_init then return real_init end
                            return function(_p, boss, ...)
                                restore_rbi()
                                local res = pack(real_init(data, boss, ...))
                                install_rbi(boss)
                                return unpack(res, 1, res.n)
                            end
                        elseif k == "post" then
                            local real_post = data.post
                            if not real_post then return real_post end
                            return function(boss, _p, ...)
                                restore_rbi()
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
            local result = pack(orig(self, call_base, call_data, ...))
            restore_rbi()
            if not post_changed then
                pcall(BossNames.rename, result[1], base, data, self)
            end
            return unpack(result, 1, result.n)
        end
    end
end

return _M
