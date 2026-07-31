local _M = {}

function _M:replaceFormat(func)
    if type(func) == "function" then
        return function(...)
            local format = string.format
            local string_recursive
            string.format = function(...)
                if string_recursive then return format(...)  end
                string_recursive = true
                local args = { ... }
                for k, v in ipairs(args) do
                    args[k] = type(v) == "string" and _t(v) or v
                end
                local res = string.tformat(unpack(args))
                string_recursive = nil
                return res
            end
            local ok, res = pcall(func, ...)
            string.format = format
            if not ok then error(res) end
            return _t(res)
        end
    end
    if type(func) == "string" then
        return _t(func)
    end
    return func
end
return _M