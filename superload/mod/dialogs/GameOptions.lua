local _M = loadPrevious(...)
local TreeList = require"engine.ui.TreeList"
local i18nhelper =require"engine.i18nhelper"
function _M:switchTo(kind)
    self['generateList'..kind:capitalize()](self)
    local list_size = #self.list
    local _TString = string.toTString
    string.toTString = function(s)
        return _TString(_t(s, "Game Options"))
    end
    self:triggerHook{"GameOptions:generateList", list=self.list, kind=kind}
    string.toTString = _TString

    for i = list_size + 1, #self.list do
        local s = self.list[i].status
        self.list[i].status = i18nhelper:replaceFormat(s)
    end

    self.c_list = TreeList.new{width=math.floor((self.iw - self.vsep.w)/2), height=self.ih - 10, scrollbar=true, columns={
        {width=60, display_prop="name"},
        {width=40, display_prop="status"},
    }, tree=self.list, fct=function(item) end, select=function(item, sel) self:select(item) end}
    if self.uis and self.uis[2] then
        self:replaceUI(self.uis[2].ui, self.c_list)
    end
end
return _M