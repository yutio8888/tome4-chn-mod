local _M = loadPrevious(...)

local _newBirthDescriptor = _M.newBirthDescriptor
function _M:newBirthDescriptor(t, ...)
    if t.locked_desc then
        local locked = t.locked_desc
        if type(locked) == "string" then
            t.locked_desc = _t(locked)
        end
        if type(locked) == "function" then
            t.locked_desc = function(...)
                local res = locked(...)
                return _t(res)
            end
        end
    end
    if t.desc then
        if type(t.desc) == "string" then
            t.desc = _t(t.desc)
        end
        if type(t.desc) == "table" then
            for k, v in ipairs(t.desc) do
                t.desc[k] = _t(v)
            end
        end
    end
    return _newBirthDescriptor(self,t, ...)
end

return _M