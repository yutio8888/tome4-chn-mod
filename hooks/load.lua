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

class:bindHook("Chat:invoke", function(self, data)
    if self.name == "command-staff" and self.player.is_first_time_souls then
        if not (self.player:hasStaffWeapon() and self.player:hasStaffWeapon().is_bonestaff
                and self.player:knowTalent(self.player.T_NECROTIC_AURA) and self.player:knowTalent(self.player.T_CALL_OF_THE_CRYPT)) then
            data.id = "welcome"
        end
    end
end)
