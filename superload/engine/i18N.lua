local _M = loadPrevious(...)
local _t2 = _M.t
function _M:t(lc, src, dst, tag, ...)
    return _t2(self, lc, src, dst, tag or "_t", ...)
end

return _M

