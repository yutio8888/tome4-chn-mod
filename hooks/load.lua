local _popup = engine.ui.Dialog.listPopup
function engine.ui.Dialog:listPopup(title, text, list, ...)
    title = _t(title) or title
    text = _t(text) or text
    for k ,v in pairs(list) do
        list[k] = type(v) == "string" and _t(v) or v
    end
    return _popup(self, title, text, list, ...)
end

local class = require"engine.class"
local i18nhelper = require"engine.i18nhelper"
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