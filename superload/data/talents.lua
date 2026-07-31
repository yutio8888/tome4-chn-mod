local _M = loadPrevious(...)

if "yes" == config.settings.tome.nullpack_new_alchemy then
    local _info = Talents.talents_def.T_BODY_OF_FIRE.info
    Talents.talents_def.T_BODY_OF_FIRE.info = function(self, t)
        if not game:isAddonActive("nullpackreloaded") then return _info(self, t) end
        local ok, res = pcall(function()
        local onhitdam = t.getFireDamageOnHit(self, t)
        local insightdam = t.getFireDamageInSight(self, t)
        local res = t.getResistance(self, t)
        local repair = t.getGolemRepairChance(self, t)
        local max_repair = t.getGolemRepairMax(self, t)
        return ([[Turn your body into pure flame, increasing your fire resistance by %d%%, burning any creatures attacking you for %0.2f fire damage, and projecting %d random slow-moving fire bolts per turn at targets in sight, doing %0.2f fire damage with each bolt.
  The projectiles safely go through your friends without harming them.
  While this talent and Flame Infusion are both sustained, if your alchemical bombs hit your golem, there is a %d%% chance that each negative physical or magical effect will be removed, up to %d effect%s maximum.
  The damage and resistance will increase with your Spellpower.]]):
        tformat(res, onhitdam, math.floor(self:getTalentLevel(t)), insightdam, repair, max_repair, (max_repair > 1) and 's' or '')
        end)
        if not ok then
            return _info(self, t)
        else
            return res end
        end
end

-- in case some bug prevents these important skills from functioning
local flex = Talents.talents_def['T_FLEXIBLE_COMBAT']
flex.callbackOnActBase = function(self, t)
    self.__unarmed_attack_on_hit = nil
end

local oob = Talents.talents_def['T_ORB_OF_THAUMATURGY']
if oob then
    oob.callbackOnActBase = function(self, t)
        self._orb_of_thaumaturgy_recurs = nil
    end
end
return _M