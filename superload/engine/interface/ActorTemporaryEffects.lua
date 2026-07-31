local _M = loadPrevious(...)
local i18nhelper = require"engine.i18nhelper"
local _newEffect = _M.newEffect
function _M:newEffect(t)
    t.long_desc = i18nhelper:replaceFormat(t.long_desc)
    if t.on_gain then
        local old_on_gain = t.on_gain
        t.on_gain = function(self, err)
            local res = { old_on_gain(self, err) }
            for i, v in ipairs(res) do res[i] = type(v) == "string" and  _t(v) or v end
            return unpack(res)
        end
    end
    if t.on_lose then
        local old_on_lose = t.on_lose
        t.on_lose = function(self, err)
            local res = { old_on_lose(self, err) }
            for i, v in ipairs(res) do res[i] = type(v) == "string" and  _t(v) or v end
            return unpack(res)
        end
    end
    _newEffect(self, t)
end

return _M