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
local Tab = require "engine.ui.Tab"

-- init stores _t"off"/_t"main" in self.equip_set, but on_change and
-- updateEquipDollRefs compare it with "off"/"main": in Chinese the first
-- switch picked the wrong set and later titles/logs showed English. Keep the
-- internal value in English and translate only for display.
if not rawget(_M, "__chn_init") then
    _M.__chn_init = true
    local _init = _M.init
    function _M:init(...)
        local res = {_init(self, ...)}
        local tab = self.c_equipment
        if type(tab) ~= "table" or type(tab.generate) ~= "function" or type(tab.on_change) ~= "function" then
            return unpack(res, 1, table.maxn(res))
        end
        self.equip_set = self.actor.off_weapon_slots and "off" or "main"
        tab.generate = function(tab)
            tab.title = ("[E]quipment: %s set"):tformat(_t(self.equip_set))
            Tab.generate(tab)
        end
        tab.on_change = function(s)
            if not self.actor.quickSwitchWeapons then return end
            if s then
                if self.last_tab == "equipment" then
                    local switch_set = self.equip_set == "off" and "main" or "off"
                    if self:updateEquipDollRefs(switch_set) then
                        self.equip_set = switch_set
                        game.logPlayer(self.actor, "#RED#Displaying %s set for %s (equipment NOT switched)", _t(self.equip_set), self.actor:getName():capitalize())
                    end
                end
                self:switchTo("equipment")
                self.c_equipment:generate() -- Force redraw
            end
        end
        tab:generate()
        return unpack(res, 1, table.maxn(res))
    end
end

return _M