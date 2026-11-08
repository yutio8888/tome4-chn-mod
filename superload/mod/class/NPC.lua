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

-- Some emote_random lists hold bare literals (tome-orcs vaporous-emporium
-- male citizens) and the resolved text is stored in the NPC, so translate
-- at display time; already translated text has no entry and is unchanged.
if not rawget(_M, "__chn_doEmote") then
    _M.__chn_doEmote = true
    local _doEmote = _M.doEmote
    function _M:doEmote(text, ...)
        if type(text) == "string" then text = _t(text) end
        return _doEmote(self, text, ...)
    end
end

return _M