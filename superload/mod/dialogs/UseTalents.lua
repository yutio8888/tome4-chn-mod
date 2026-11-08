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
local TreeList = require "engine.ui.TreeList"

-- The columns are built inside init: the status column uses the shared
-- _t"Active" (also used by other dialogs), and the hotkey/mouse columns show
-- the literals "H.Key N", "LeftClick" and "MiddleClick". Columns are matched
-- by their header; anything not recognised is left untouched.
local function fixColumns(cols)
    local active_key = "Active##use_talents"
    local active = _t(active_key)
    for _, col in ipairs(cols) do
        local prop = col.display_prop
        if col.name == _t"Status" and type(prop) == "function" and active ~= active_key then
            local prefix = "#LIGHT_GREEN#".._t"Active"
            col.display_prop = function(item)
                local res = prop(item)
                if type(res) == "string" and res:sub(1, #prefix) == prefix then
                    res = "#LIGHT_GREEN#"..active..res:sub(#prefix + 1)
                end
                return res
            end
        elseif col.name == _t"Hotkey" and prop == "hotkey" then
            -- The fixed 75px column fits "H.Key 10" but clips the wider
            -- Chinese label ("快捷键 10" loses its last digit), so widen it.
            if ("H.Key %d"):tformat(10) ~= "H.Key 10" and type(col.width) == "table" and col.width[2] == "fixed" and (col.width[1] or 0) < 95 then
                col.width = {95, "fixed"}
            end
            col.display_prop = function(item)
                local res = util.getval(item.hotkey, item)
                if type(res) == "string" then
                    local n = res:match("^H%.Key (%d+)$")
                    if n then res = ("H.Key %d"):tformat(tonumber(n)) end
                    return res
                end
                if type(res) == "table" then return res end
                return tostring(res or "")
            end
        elseif col.name == _t"Mouse Click" and type(prop) == "function" then
            col.display_prop = function(item)
                local res = prop(item)
                if res == "LeftClick" or res == "MiddleClick" then res = _t(res) end
                return res
            end
        end
    end
end

if not rawget(_M, "__chn_init") then
    _M.__chn_init = true
    local _init = _M.init
    function _M:init(...)
        local raw_new = rawget(TreeList, "new")
        local new = TreeList.new
        TreeList.new = function(t, ...)
            rawset(TreeList, "new", raw_new)
            if type(t) == "table" and type(t.columns) == "table" then
                pcall(fixColumns, t.columns)
            end
            return new(t, ...)
        end
        local res = {pcall(_init, self, ...)}
        rawset(TreeList, "new", raw_new)
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, table.maxn(res))
    end
end

return _M