-- Chinese-only display fixes for two Embers of Rage descriptions whose
-- upstream dynamic arguments do not match what the code actually applies.
-- Game mechanics, effect parameters, temporary-value ids and save data are
-- never touched; on any unexpected shape the original function is used.
--
-- 1. Bloodstream (data/talents/steam/sawmaiming.lua): info passes
--    getDamageInc as the bleed figure, but action multiplies the existing
--    EFF_CUT power by getDamage/100. The Chinese text shows getDamage.
-- 2. AUTOMATED_REPAIR_SYSTEM (data/timed_effects/other.lua): activate
--    overwrites eff.heal/eff.resist/eff.life with addTemporaryValue ids, and
--    long_desc formats those ids. The Chinese text reads the increments the
--    engine stored for those ids (self.compute_vals[id]), read-only.

local M = {}

local BLOODSTREAM_FMT = [[You "gently" slam your saws into the wounds of a creature, dealing %d%% weapon damage and deepening the wounds.
		All bleeding wounds durations are increased by %d turns and the damage by %d%% (this may be done only once per bleeding effect).
		When this happens a gush of blood is projected in a narrow cone of radius 4, dealing %0.2f physical damage to all creatures.
		The power and damage improves with your Steampower.
		#{italic}#The marvels of technology, now at the service of true butchery!#{normal}#]]

local REPAIR_FMT = "Engaged in automated repairs, preventing any action but increasing life regen by %d, all resistances by %d%% and preventing death until falling below -%d life."

M.BLOODSTREAM_FMT = BLOODSTREAM_FMT
M.REPAIR_FMT = REPAIR_FMT

local function is_zh()
    return config and config.settings and config.settings.locale == "zh_hans"
end
M.is_zh = is_zh

local warned = {}
local function warn_once(key, err)
    if warned[key] then return end
    warned[key] = true
    print("[chn-mod] dynamic description fallback for "..key..": "..tostring(err))
end

function M.installBloodstream(def, damDesc, physical)
    if not def or def.__chn_bloodstream then return false end
    if type(def.info) ~= "function" or type(def.getDamage) ~= "function"
        or type(def.getDuration) ~= "function" or type(damDesc) ~= "function" or physical == nil then
        return false
    end
    local info = def.info
    def.info = function(self, t, ...)
        if not is_zh() then return info(self, t, ...) end
        local ok, res = pcall(function()
            local dam = t.getDamage(self, t)
            return BLOODSTREAM_FMT:tformat(
                self:combatTalentWeaponDamage(t, 0.3, 1.1) * 100,
                t.getDuration(self, t),
                dam,
                damDesc(self, physical, dam))
        end)
        if ok and res ~= nil then return res end
        warn_once("T_BLOODSTREAM", res)
        return info(self, t, ...)
    end
    def.__chn_bloodstream = true
    return true
end

-- Returns heal, resist, life increments stored by addTemporaryValue for the
-- ids kept in eff, or nil when anything does not have the expected shape.
function M.repairIncrements(actor, eff)
    if type(actor) ~= "table" or type(eff) ~= "table" then return nil end
    local vals = rawget(actor, "compute_vals")
    if type(vals) ~= "table" then return nil end
    local hid, rid, lid = eff.heal, eff.resist, eff.life
    if type(hid) ~= "number" or type(rid) ~= "number" or type(lid) ~= "number" then return nil end
    if hid == rid or hid == lid or rid == lid then return nil end
    local heal, res, life = vals[hid], vals[rid], vals[lid]
    if type(heal) ~= "number" or type(life) ~= "number" or type(res) ~= "table" then return nil end
    local all = res.all
    if type(all) ~= "number" then return nil end
    return heal, all, -life
end

function M.installAutomatedRepair(def)
    if not def or def.__chn_automated_repair then return false end
    if type(def.long_desc) ~= "function" then return false end
    local long_desc = def.long_desc
    def.long_desc = function(self, eff, ...)
        if not is_zh() then return long_desc(self, eff, ...) end
        local heal, resist, life = M.repairIncrements(self, eff)
        if heal == nil then return long_desc(self, eff, ...) end
        local ok, res = pcall(function() return REPAIR_FMT:tformat(heal, resist, life) end)
        if ok and res ~= nil then return res end
        warn_once("EFF_AUTOMATED_REPAIR_SYSTEM", res)
        return long_desc(self, eff, ...)
    end
    def.__chn_automated_repair = true
    return true
end

function M.install()
    local ok_t, ActorTalents = pcall(require, "engine.interface.ActorTalents")
    local ok_e, ActorTemporaryEffects = pcall(require, "engine.interface.ActorTemporaryEffects")
    if ok_t and ActorTalents and ActorTalents.talents_def then
        local ok_d, DamageType = pcall(require, "engine.DamageType")
        local physical = ok_d and DamageType and DamageType.PHYSICAL or nil
        M.installBloodstream(ActorTalents.talents_def.T_BLOODSTREAM, ActorTalents.damDesc, physical)
    end
    if ok_e and ActorTemporaryEffects and ActorTemporaryEffects.tempeffect_def then
        M.installAutomatedRepair(ActorTemporaryEffects.tempeffect_def.EFF_AUTOMATED_REPAIR_SYSTEM)
    end
end

return M
