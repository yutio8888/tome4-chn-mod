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

local function pack(...) return {n = select("#", ...), ...} end

-- add_name is appended untranslated, so the shield " (#ARMOR#, #SHIELD#)"
-- keeps a half-width comma between already translated full-width parts.
-- Swap in the translated add_name for the duration of the call only.
if not rawget(_M, "__chn_getName") then
    _M.__chn_getName = true
    local _getName = _M.getName
    function _M:getName(...)
        local add_name = self.add_name
        if type(add_name) == "string" then
            local tr = _t(add_name, "entity add_name")
            if tr ~= add_name then
                local raw = rawget(self, "add_name")
                self.add_name = tr
                local res = pack(pcall(_getName, self, ...))
                rawset(self, "add_name", raw)
                if not res[1] then error(res[2], 0) end
                return unpack(res, 2, res.n)
            end
        end
        return _getName(self, ...)
    end
end

-- The seven property lines (resistances, damage, penetration...) show
-- _t"all", a key shared with the online events option and psionic shields.
-- Only inside this call, give "all" the item-property wording.
if not rawget(_M, "__chn_getTextualDesc") then
    _M.__chn_getTextualDesc = true
    local _getTextualDesc = _M.getTextualDesc
    function _M:getTextualDesc(...)
        local all_key = "all##item_property"
        local all = _t(all_key)
        if all == all_key then return _getTextualDesc(self, ...) end
        local old_t = _G._t
        _G._t = function(s, tag, ...)
            if s == "all" and (tag == nil or tag == "_t") then return all end
            return old_t(s, tag, ...)
        end
        local res = pack(pcall(_getTextualDesc, self, ...))
        _G._t = old_t
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end
end

-- Same as the 1.7.6 Object:getShortName (only used by the equipment doll and
-- weapon tooltips) except that the keyword separator is translatable.
if not rawget(_M, "__chn_getShortName") then
    _M.__chn_getShortName = true
    function _M:getShortName(t)
        if not self.short_name then return self:getName(t) end

        t = t or {}
        t.no_add_name = true

        local qty = self:getNumber()
        local identified = t.force_id or self:isIdentified()
        local name = _t(self.short_name, "entity short_name") or _t"object"

        if not identified then
            local _, c = self:getDisplayColor(true)
            if self.unique then
                name = ("%s, %sspecial#LAST#"):tformat(self:getUnidentifiedName(), c)
            elseif self.egoed then
                name = ("%s, %sego#LAST#"):tformat(name, c)
            end
        elseif self.keywords and next(self.keywords) then
            -- I18N translate keywords.
            local ks = table.keys(self.keywords)
            local k = {}
            for i, key in ipairs(ks) do
                k[i] = _t(key, "entity keyword")
            end
            table.sort(k)
            local sep_key = ", ##short_name"
            local sep = _t(sep_key)
            if sep == sep_key then sep = ", " end
            name = name..sep..table.concat(k, sep)
        end

        if not t.do_color then
            if qty == 1 or t.no_count then return name
            else return qty.." "..name
            end
        else
            local _, c = self:getDisplayColor()
            local ds = t.no_image and "" or self:getDisplayString()
            if qty == 1 or t.no_count then return c..ds..name.."#LAST#"
            else return c..qty.." "..ds..name.."#LAST#"
            end
        end
    end
end

return _M