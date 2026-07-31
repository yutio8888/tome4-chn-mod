local _M = loadPrevious(...)

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
