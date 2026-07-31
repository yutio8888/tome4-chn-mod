local _M = loadPrevious(...)
local helper = require"engine.i18nhelper"

local _newTalent = _M.newTalent
function _M:newTalent(t, ...)
    local info = t.info
    if type(info) == "string" then
        t.info = _t(info)
    end
    if type(info) == "function" then
        t.info = helper:replaceFormat(info)
    end
    _newTalent(self, t, ...)
end

local _newTalentType = _M.newTalentType
function _M:newTalentType(t, ...)
    if t.description then
        t.description = _t(t.description)
    end
    _newTalentType(self, t, ...)
end

return _M