local _M = loadPrevious(...)

local _dt = _M.newDamageType
function _M:newDamageType(t)
    t.name = type(t.name) == "string" and _t(t.name, "damage type") or t.name
    _dt(self, t)
end

return _M