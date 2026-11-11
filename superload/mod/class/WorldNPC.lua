local _M = loadPrevious(...)
local creature_subtype = dofile("/hooks/chn-mod/creature_subtype.lua")

if not rawget(_M, "__chn_creature_subtype_tooltip") then
    _M.__chn_creature_subtype_tooltip = true
    local tooltip = _M.tooltip
    function _M:tooltip(...)
        local ts = tooltip(self, ...)
        if ts then creature_subtype.fixTooltip(self, ts) end
        return ts
    end
end

return _M
