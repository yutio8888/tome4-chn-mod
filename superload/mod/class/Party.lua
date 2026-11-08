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

-- Game:newGame calls setPlayer before the birther renames the character, so
-- the "control switched to player" log line is noise. game.state does not
-- exist yet at that point (it always does after loading a save).
if not rawget(_M, "__chn_setPlayer") then
    _M.__chn_setPlayer = true
    local _setPlayer = _M.setPlayer
    function _M:setPlayer(...)
        if not game or game.state or not game.logPlayer then
            return _setPlayer(self, ...)
        end
        local raw_logPlayer = rawget(game, "logPlayer")
        game.logPlayer = function() end
        local res = {pcall(_setPlayer, self, ...)}
        rawset(game, "logPlayer", raw_logPlayer)
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, table.maxn(res))
    end
end

return _M