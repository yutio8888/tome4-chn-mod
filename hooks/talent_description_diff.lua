local _M = {}

-- Talent descriptions are tokenized on whitespace by the base game.  Chinese
-- text normally has no whitespace around formatted numbers, so a value change
-- makes the whole surrounding phrase look different.
local function is_digit(c)
    return c and c >= "0" and c <= "9"
end

local function number_end(s, start)
    local i = start
    local c = s:sub(i, i)

    if c == "+" or c == "-" then
        local prev = start > 1 and s:sub(start - 1, start - 1)
        if start == 1 or not is_digit(prev) then
            i = i + 1
        end
    end

    local integer_start = i
    while is_digit(s:sub(i, i)) do i = i + 1 end
    local has_integer = i > integer_start

    local has_fraction = false
    if s:sub(i, i) == "." and is_digit(s:sub(i + 1, i + 1)) then
        has_fraction = true
        i = i + 1
        while is_digit(s:sub(i, i)) do i = i + 1 end
    end

    if not has_integer and not has_fraction then return nil end

    local exponent = s:sub(i, i)
    if exponent == "e" or exponent == "E" then
        local exponent_end = i + 1
        local sign = s:sub(exponent_end, exponent_end)
        if sign == "+" or sign == "-" then exponent_end = exponent_end + 1 end
        local exponent_start = exponent_end
        while is_digit(s:sub(exponent_end, exponent_end)) do exponent_end = exponent_end + 1 end
        if exponent_end > exponent_start then i = exponent_end end
    end

    if s:sub(i, i) == "%" then i = i + 1 end
    return i - 1
end

local function split_numeric(s)
    local parts = {}
    local text_start = 1
    local i = 1

    while i <= #s do
        local finish = number_end(s, i)
        if finish then
            if text_start < i then
                parts[#parts + 1] = {kind = "text", value = s:sub(text_start, i - 1)}
            end
            parts[#parts + 1] = {kind = "number", value = s:sub(i, finish)}
            i = finish + 1
            text_start = i
        else
            i = i + 1
        end
    end

    if text_start <= #s then
        parts[#parts + 1] = {kind = "text", value = s:sub(text_start)}
    end
    return parts
end

local function compatible(parts)
    local base = parts[1]
    if not base or #base == 0 then return false end

    local has_number = false
    for i, part in ipairs(base) do
        if part.kind == "number" then has_number = true end
        for level = 2, #parts do
            local other = parts[level]
            if #other ~= #base or not other[i] or other[i].kind ~= part.kind then return false end
            if part.kind == "text" and other[i].value ~= part.value then return false end
        end
    end
    return has_number
end

local function add_pair_diff(new, old, res, on_diff)
    if type(new) ~= "string" or type(old) ~= "string" then return false end
    local parts = {split_numeric(new), split_numeric(old)}
    if not compatible(parts) then return false end

    for i, new_part in ipairs(parts[1]) do
        local old_part = parts[2][i]
        if new_part.value == old_part.value then
            res:add(new_part.value)
        else
            on_diff(new_part.value, old_part.value, res)
        end
    end
    return true
end

local function add_multi_diff(diffs, res, on_diff)
    local parts = {}
    for i, diff in ipairs(diffs) do
        if type(diff.str) ~= "string" then return false end
        parts[i] = split_numeric(diff.str)
    end
    if not compatible(parts) then return false end

    for part_index, base_part in ipairs(parts[1]) do
        local same = true
        for level = 2, #parts do
            if parts[level][part_index].value ~= base_part.value then
                same = false
                break
            end
        end

        if same then
            res:add(base_part.value)
        else
            local numeric_diffs = {}
            for level, diff in ipairs(diffs) do
                numeric_diffs[level] = {id = diff.id, str = parts[level][part_index].value}
            end
            on_diff(numeric_diffs, res)
        end
    end
    return true
end

function _M.install()
    if not config or not config.settings or config.settings.locale ~= "zh_hans" then return false end
    if not tstring or tstring.__chn_mod_numeric_diff then return false end

    local old_diff_with = tstring.diffWith
    local old_diff_multi = tstring.diffMulti
    if type(old_diff_with) ~= "function" or type(old_diff_multi) ~= "function" then return false end

    function tstring:diffWith(str2, on_diff)
        return old_diff_with(self, str2, function(new, old, res)
            if not add_pair_diff(new, old, res, on_diff) then on_diff(new, old, res) end
        end)
    end

    function tstring:diffMulti(list, on_diff)
        return old_diff_multi(self, list, function(diffs, res)
            if not add_multi_diff(diffs, res, on_diff) then on_diff(diffs, res) end
        end)
    end

    tstring.__chn_mod_numeric_diff = true
    return true
end

_M.splitNumeric = split_numeric

return _M
