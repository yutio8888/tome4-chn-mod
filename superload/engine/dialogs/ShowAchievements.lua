-- chn-mod - Modified Chinese Translation
-- ToME4 (Tales of Maj'Eyal) Chinese localization addon
-- Copyright (C) 2026 yutio888
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
-- Upstream: ToME4 and official DLCs are Copyright (C) 2009-2019
-- Nicolas Casalini "DarkGod" (darkgod@te4.org), GPL v3 or later.
-- This addon is a derivative work released under the same license.

local _M = loadPrevious(...)

-- DLC achievement categories are bare literals ("Embers of Rage"); their
-- translations already exist under other tags and are reachable by _t.
if not rawget(_M, "__chn_generateList") then
    _M.__chn_generateList = true
    local _generateList = _M.generateList
    function _M:generateList(...)
        local res = {_generateList(self, ...)}
        for _, item in ipairs(self.list or {}) do
            if type(item.category) == "string" then item.category = _t(item.category) end
        end
        return unpack(res, 1, table.maxn(res))
    end
end

return _M