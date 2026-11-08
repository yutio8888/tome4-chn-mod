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

-- getActorPortrait often builds a plain engine.Entity{name=actor.name}, whose
-- getName returns the raw English name for the portrait name plate.
if not rawget(_M, "__chn_getActorPortrait") then
    _M.__chn_getActorPortrait = true
    local _getActorPortrait = _M.getActorPortrait
    function _M:getActorPortrait(actor, ...)
        local e = _getActorPortrait(self, actor, ...)
        local src = type(actor) == "table" and (actor.replace_display or actor)
        if type(e) == "table" and src and e ~= src and e ~= actor and type(e.name) == "string" and e.name == src.name then
            -- Same lookup as Actor:getName; objects' getName would add counts.
            e.name = _t(e.name, "entity name")
        end
        return e
    end
end

return _M