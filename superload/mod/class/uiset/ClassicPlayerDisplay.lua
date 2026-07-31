local _M = loadPrevious(...)
--- Resize the display area
---
local I18N = require "engine.I18N"
local _resize = _M.resize
function _M:resize(x, y, w, h)
    _resize(self, x, y, w, h)
    local locale = I18N:getLocalesData()
    if locale == "zh_hans" or locale ==  "zh_hant"  then
        self.bars_x = self.font_w * 5
        self.bars_w = self.w - self.bars_x - 5
    end
end

return _M