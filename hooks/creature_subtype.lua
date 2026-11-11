local M = {}
local light_key = "light##creature_subtype"

local function translatedLight()
    local light = _t(light_key)
    if light ~= light_key then return light:capitalize() end
end

function M.fixTooltip(actor, tooltip)
    if actor.subtype ~= "light" then return end
    local light = translatedLight()
    if not light then return end

    -- Both actor tooltips put their type and subtype right after the name line.
    -- tstring:add stores each argument as a separate token.
    local actor_type = _t(actor.type, "entity type"):capitalize()
    local old_subtype = _t("light", "entity subtype"):capitalize()
    for i, token in ipairs(tooltip) do
        if token == true then
            if tooltip[i + 1] == actor_type and tooltip[i + 2] == " / "
                and tooltip[i + 3] == old_subtype and tooltip[i + 4] == true then
                tooltip[i + 3] = light
            end
            return
        end
    end
end

function M.installPredator(effect)
    if not effect or effect.__chn_creature_subtype then return end
    local long_desc = effect.long_desc
    effect.long_desc = function(actor, eff, ...)
        local desc = long_desc(actor, eff, ...)
        local level = game.level
        local subtypes = level and table.get(actor, "mark_prey2", level.id)
        if not subtypes or subtypes.light == nil then return desc end
        local light = translatedLight()
        if not light then return desc end

        -- Match a whole entry in the subtype list, after the named prey list.
        local header = ("\n%d%% Received damage reduction against:"):tformat(eff.power)
        local _, header_end = desc:find(header, 1, true)
        if not header_end then return desc end
        local entry = "\n- #ffa0ff#%s#LAST#"
        local old_line = entry:tformat(_t("light", "entity subtype"):capitalize())
        local first, last = (desc .. "\n"):find(old_line .. "\n", header_end + 1, true)
        if not first then return desc end
        return desc:sub(1, first - 1) .. entry:tformat(light) .. desc:sub(last)
    end
    effect.__chn_creature_subtype = true
end

return M
