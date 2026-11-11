-- The engine only auto-loads an addon's data/locales/<lang>.lua
-- (see Module.lua loadLocale), so standalone translation files must be
-- loaded explicitly. They carry a locale header and register into zh_hans.
local I18N = require("engine.I18N")
I18N:loadLocale("/data-chn-mod/null_translation.lua")
I18N:loadLocale("/data-chn-mod/chn_supplement.lua")

-- Keep level-up comparisons focused on the changing numbers even when a
-- Chinese sentence has no whitespace around them.
local talent_description_diff = dofile("/hooks/chn-mod/talent_description_diff.lua")
talent_description_diff.install()

local _popup = engine.ui.Dialog.listPopup
function engine.ui.Dialog:listPopup(title, text, list, ...)
    title = _t(title) or title
    text = _t(text) or text
    for k ,v in pairs(list) do
        list[k] = type(v) == "string" and _t(v) or v
    end
    return _popup(self, title, text, list, ...)
end

-- Some popups pass bare literals (e.g. Player:hotkeyPageTutorial), so
-- translate string titles and texts here; tstrings are left alone.
if not engine.ui.Dialog.__chn_simple_popups then
    engine.ui.Dialog.__chn_simple_popups = true
    local _simplePopup = engine.ui.Dialog.simplePopup
    if _simplePopup then
        function engine.ui.Dialog:simplePopup(title, text, ...)
            if type(title) == "string" then title = _t(title) end
            if type(text) == "string" then text = _t(text) end
            return _simplePopup(self, title, text, ...)
        end
    end
    local _simpleLongPopup = engine.ui.Dialog.simpleLongPopup
    if _simpleLongPopup then
        function engine.ui.Dialog:simpleLongPopup(title, text, ...)
            if type(title) == "string" then title = _t(title) end
            if type(text) == "string" then text = _t(text) end
            return _simpleLongPopup(self, title, text, ...)
        end
    end
end

local class = require"engine.class"
local i18nhelper = require"engine.i18nhelper"
local creature_subtype = dofile("/hooks/chn-mod/creature_subtype.lua")
class:bindHook("Actor:tooltip", function(self, data)
    creature_subtype.fixTooltip(self, data.ts)
end)

class:bindHook("Entity:loadList", function(self, data)
    if data.file == "/data-nullpackreloaded/general/special-artifacts.lua" then
        data.res["NULL_TIMEKEEPER"].desc = _t(data.res["NULL_TIMEKEEPER"].desc)
        data.res["NULL_TIMEKEEPER"].unided_name = _t(data.res["NULL_TIMEKEEPER"].unided_name)
        data.res["NULL_TIMEKEEPER"].old_special_desc = data.res["NULL_TIMEKEEPER"].special_desc
        data.res["NULL_TIMEKEEPER"].special_desc = function(self)
            return _t(self.old_special_desc(self))
        end
        data.res["SHARD_OF_WINTERTIDE"].desc = _t(data.res["SHARD_OF_WINTERTIDE"].desc)
        data.res["SHARD_OF_WINTERTIDE"].unided_name = _t(data.res["SHARD_OF_WINTERTIDE"].unided_name)
        data.res["VIPERS_RETORT"].desc = _t(data.res["VIPERS_RETORT"].desc)
        data.res["VIPERS_RETORT"].unided_name = _t(data.res["VIPERS_RETORT"].unided_name)
        data.res["SPINE_OF_THE_SPIRE"].desc = _t(data.res["SPINE_OF_THE_SPIRE"].desc)
        data.res["SPINE_OF_THE_SPIRE"].unided_name = _t(data.res["SPINE_OF_THE_SPIRE"].unided_name)
        for k, v in ipairs(data.res) do
            if v.name == "Jade Fervor" then
                v.desc = _t(v.desc)
                v.old_special_desc = v.special_desc
                v.special_desc = function(self)
                    return _t(self.old_special_desc(self))
                end
                v.special_desc = _t(v.special_desc)
                v.unided_name = _t(v.unided_name)
                v.combat.special_on_crit.desc = _t(v.combat.special_on_crit.desc)
            end
            if v.name == "Stained Honor" then
                v.desc = _t(v.desc)
                v.unided_name = _t(v.unided_name)
            end
        end
    end
end)

class:bindHook("Chat:invoke", function(self, data)
    if self.name == "command-staff" and self.player.is_first_time_souls then
        if not (self.player:hasStaffWeapon() and self.player:hasStaffWeapon().is_bonestaff
                and self.player:knowTalent(self.player.T_NECROTIC_AURA) and self.player:knowTalent(self.player.T_CALL_OF_THE_CRYPT)) then
            data.id = "welcome"
        end
    end
end)

-- Fixes that need DLC data, which the DLCs only define in their own
-- ToME:load hooks; this addon's hooks are bound after theirs (higher weight).
class:bindHook("ToME:load", function(self, data)
    local ActorTemporaryEffects = require("engine.interface.ActorTemporaryEffects")
    creature_subtype.installPredator(ActorTemporaryEffects.tempeffect_def.EFF_PREDATOR)

    -- Resources without a CharacterSheet.status_text (Cults insanity) return
    -- a string meant to be formatted once more ("%%"), as the uisets do.
    local ok, ActorResource = pcall(require, "engine.interface.ActorResource")
    if ok and ActorResource and ActorResource.resources_def then
        for _, def in ipairs(ActorResource.resources_def) do
            if type(def.status_text) == "function" and not table.get(def.CharacterSheet, "status_text") then
                local status_text = def.status_text
                def.CharacterSheet = def.CharacterSheet or {}
                def.CharacterSheet.status_text = function(act, ...)
                    local text = status_text(act, ...)
                    if type(text) ~= "string" then return text end
                    local fok, res = pcall(string.format, text)
                    return fok and res or text
                end
            end
        end
    end

    -- Orcs replaces class/subclass locked_desc with functions after the
    -- descriptors were created, so Birther:newBirthDescriptor never saw them.
    local Birther = require("engine.Birther")
    for _, kind in ipairs{"class", "subclass"} do
        for _, d in ipairs(Birther.birth_descriptor_def[kind] or {}) do
            if type(d.locked_desc) == "function" and not d.__chn_locked_desc then
                local locked_desc = d.locked_desc
                d.locked_desc = function(...)
                    local res = locked_desc(...)
                    return type(res) == "string" and _t(res) or res
                end
                d.__chn_locked_desc = true
            end
        end
    end
end)
