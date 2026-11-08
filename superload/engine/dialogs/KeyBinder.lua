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

-- Group headers are group:capitalize() without _t. Four movement binds use
-- group=_t"movement", so in Chinese they formed a second "移动" group;
-- groups with the same displayed name are merged.
local function groupName(group)
    local cap = group:capitalize()
    local key = cap.."##keybind_group"
    local name = _t(key)
    if name == key then name = _t(cap) end
    return name
end

if not rawget(_M, "__chn_generateList") then
    _M.__chn_generateList = true
    local _generateList = _M.generateList
    function _M:generateList(...)
        local res = {_generateList(self, ...)}
        if type(self.tree) ~= "table" then return unpack(res, 1, table.maxn(res)) end
        local by_name, tree = {}, {}
        for _, node in ipairs(self.tree) do
            local first = type(node.nodes) == "table" and node.nodes[1]
            local group = first and first.k and first.k.group
            if type(group) == "string" then
                local name = groupName(group)
                local prev = by_name[name]
                if prev then
                    for _, item in ipairs(node.nodes) do prev.nodes[#prev.nodes+1] = item end
                else
                    node.name = tstring{{"font","bold"}, {"color","GOLD"}, name, {"font","normal"}}
                    node.sortname = name
                    by_name[name] = node
                    tree[#tree+1] = node
                end
            else
                tree[#tree+1] = node
            end
        end
        table.sort(tree, function(a, b) return tostring(a.sortname) < tostring(b.sortname) end)
        self.tree = tree
        return unpack(res, 1, table.maxn(res))
    end
end

return _M