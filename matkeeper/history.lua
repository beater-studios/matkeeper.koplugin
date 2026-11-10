-- Past matches, newest first, with their logs so they can be read later.
local History = {}

History.LIMIT = 30

function History.add(list, summary, limit)
    local result = { summary }
    for _, item in ipairs(list or {}) do
        if #result >= (limit or History.LIMIT) then
            break
        end
        result[#result + 1] = item
    end
    return result
end

function History.valid(list)
    local result = {}
    for _, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" and type(item.players) == "table" and type(item.log) == "table" then
            result[#result + 1] = item
        end
    end
    return result
end

return History
