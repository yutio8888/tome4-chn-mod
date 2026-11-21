local rules = dofile("/data-chn-mod/chn_random_names.lua")
local M = {}

local function zh()
    return config and config.settings and config.settings.locale == "zh_hans"
end

local function pick(pool, key)
    -- Small integer arithmetic, exact under the Lua 5.1 number model.
    local h = 0
    for i = 1, #key do
        h = (h * 131 + key:byte(i)) % 2147483647
    end
    return pool[h % #pool + 1]
end

local function theme(obj, damage_types)
    local found
    local inc = type(obj.wielder) == "table" and obj.wielder.inc_damage
    inc = type(inc) == "table" and inc or nil
    local combat = type(obj.combat) == "table" and obj.combat or nil
    for _, kind in ipairs{"FIRE", "COLD", "LIGHTNING", "LIGHT", "DARKNESS"} do
        local id = damage_types and damage_types[kind]
        local bonus = id and inc and inc[id]
        if id and (type(bonus) == "number" and bonus > 0
            or combat and (combat.element == id or combat.damtype == id)) then
            if found then return "neutral" end
            found = kind:lower()
        end
    end
    return found or "neutral"
end

local function plain_label(s)
    -- Reject engine name/color markup and control bytes rather than trying to re-create getName.
    return type(s) == "string" and #s > 0 and not s:find("[#~&%%%c<>]")
end

function M.annotate(obj, damage_types)
    if type(obj) ~= "table" or obj.randart ~= true or rawget(obj, "__chn_randart_name")
        or not plain_label(obj.name) or type(obj.unique) ~= "string" or obj.unique == ""
        or type(obj.define_as) ~= "string" or obj.define_as == "" then return end
    local by_type = rules.base_names[obj.type]
    local base = by_type and by_type[obj.subtype]
    if not base then return end
    local name = pick(rules.pools[theme(obj, damage_types)],
        table.concat({rules.version, obj.type, obj.subtype, obj.unique, obj.define_as}, "\0"))
    -- Name/unique also guard against metadata copied by addRandartProperties and other postprocessors.
    rawset(obj, "__chn_randart_name", {
        version = rules.version, text = base .. "「" .. name .. "」",
        original = obj.name, unique = obj.unique, define_as = obj.define_as,
    })
end

function M.decorate(obj, opts, rendered)
    if not zh() or obj.randart ~= true or type(rendered) ~= "string"
        or opts and (type(opts) ~= "table" or opts.raw_name or opts.trans_only)
        or not obj:isIdentified() then return rendered end
    local meta = rawget(obj, "__chn_randart_name")
    if type(meta) ~= "table" or meta.version ~= 1 or not plain_label(meta.text)
        or meta.original ~= obj.name or meta.unique ~= obj.unique
        or meta.define_as ~= obj.define_as or not plain_label(obj.name) then return rendered end
    local original = _t(obj.name, "entity name")
    if not plain_label(original) then return rendered end
    local first, last = rendered:find(original, 1, true)
    -- In an ambiguous/custom rendering, the safest behavior is to keep the original.
    if not first or rendered:find(original, first + 1, true) then return rendered end
    return rendered:sub(1, first - 1) .. meta.text .. rendered:sub(last + 1)
end

return M
