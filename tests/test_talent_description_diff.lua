local function new_tstring(values)
    values = values or {}
    setmetatable(values, {__index = tstring})
    function values:add(...)
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if value ~= nil then self[#self + 1] = value end
        end
        return self
    end
    return values
end

tstring = setmetatable({}, {
    __call = function(_, values) return new_tstring(values) end,
})

function tstring:diffWith(str2, on_diff)
    local res = tstring{}
    for i = 1, #self do
        if type(self[i]) == "string" and self[i] ~= str2[i] then
            on_diff(self[i], str2[i], res)
        else
            res:add(self[i])
        end
    end
    return res
end

function tstring:diffMulti(list, on_diff)
    local res = tstring{}
    for i = 1, #list[1] do
        local different = false
        for level = 2, #list do
            if type(list[1][i]) == "string" and list[1][i] ~= list[level][i] then
                different = true
                break
            end
        end
        if different then
            local diffs = {}
            for level = 1, #list do diffs[level] = {id = level, str = list[level][i]} end
            on_diff(diffs, res)
        else
            res:add(list[1][i])
        end
    end
    return res
end

local function joined(value)
    local out = {}
    for _, part in ipairs(value) do out[#out + 1] = type(part) == "string" and part or "<control>" end
    return table.concat(out)
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(("%s\nexpected: %s\nactual:   %s"):format(label, expected, actual), 2)
    end
end

local function pair_diff(new, old)
    return joined(tstring{new}:diffWith(tstring{old}, function(new_value, old_value, res)
        res:add(old_value, "[->", new_value, "]")
    end))
end

local patch = dofile("hooks/talent_description_diff.lua")
config = {settings = {locale = "en_US"}}
assert(not patch.install(), "patch should not install for other locales")
config.settings.locale = "zh_hans"
assert(patch.install(), "patch should install for zh_hans")
assert(not patch.install(), "patch should only install once")

assert_equal(pair_diff("造成15点伤害", "造成10点伤害"),
    "造成10[->15]点伤害", "single integer")
assert_equal(pair_diff("造成12.75%伤害，持续4回合", "造成10.5%伤害，持续3回合"),
    "造成10.5%[->12.75%]伤害，持续3[->4]回合", "multiple decimal and percent values")
assert_equal(pair_diff("修正为+2.5，倍率为1e+06", "修正为-1.5，倍率为5e+05"),
    "修正为-1.5[->+2.5]，倍率为5e+05[->1e+06]", "signed and exponent values")
assert_equal(pair_diff("造成12-18点", "造成10-15点"),
    "造成10[->12]-15[->18]点", "unspaced numeric range")
assert_equal(pair_diff("生命-60", "生命-50"),
    "生命-50[->-60]", "signed value after non-digit text")
assert_equal(pair_diff("造成10点伤害并获得5点护盾", "造成10点伤害"),
    "造成10点伤害[->造成10点伤害并获得5点护盾]", "different structure falls back")
assert_equal(pair_diff("治疗15点生命", "造成10点伤害"),
    "造成10点伤害[->治疗15点生命]", "different text falls back")

local control = {"color", "WHITE"}
local controlled = tstring{control, "造成15点伤害"}:diffWith(tstring{control, "造成10点伤害"},
    function(new_value, old_value, res) res:add(old_value, "[->", new_value, "]") end)
assert(controlled[1] == control, "control tokens should be preserved")
assert_equal(joined(controlled), "<control>造成10[->15]点伤害", "control token comparison")

local levels = {
    tstring{"造成10点伤害，持续2回合"},
    tstring{"造成15点伤害，持续3回合"},
    tstring{"造成20点伤害，持续4回合"},
}
local multi = tstring:diffMulti(levels, function(diffs, res)
    local values = {}
    for _, diff in ipairs(diffs) do values[#values + 1] = diff.str end
    res:add("<", table.concat(values, ","), ">")
end)
assert_equal(joined(multi), "造成<10,15,20>点伤害，持续<2,3,4>回合", "multi-level comparison")

local different_levels = {
    tstring{"造成10点伤害"},
    tstring{"造成15点伤害并获得5点护盾"},
}
local fallback_multi = tstring:diffMulti(different_levels, function(diffs, res)
    res:add("<", diffs[1].str, "|", diffs[2].str, ">")
end)
assert_equal(joined(fallback_multi), "<造成10点伤害|造成15点伤害并获得5点护盾>",
    "multi-level structural changes fall back")

print("talent description numeric diff tests passed")
