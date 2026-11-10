-- Checks that every language has the same keys as Portuguese, with the same format markers.
package.path = "./?.lua;" .. package.path
local chunk = assert(loadfile("data/i18n.lua"))
setfenv(chunk, {})
local i18n = chunk()
local errors = 0

local function markers(s)
    local list = {}
    for m in s:gmatch("%%[%d%.]*[sd]") do
        list[#list + 1] = m
    end
    return table.concat(list, " ")
end

local function compare(base, other, path, lang)
    for key, value in pairs(base) do
        local here = path .. "." .. tostring(key)
        local theirs = other[key]
        if theirs == nil then
            errors = errors + 1
            print(lang .. ": missing " .. here)
        elseif type(value) == "table" then
            if type(theirs) ~= "table" then
                errors = errors + 1
                print(lang .. ": not a table " .. here)
            else
                compare(value, theirs, here, lang)
            end
        elseif type(value) == "string" and markers(value) ~= markers(theirs) then
            errors = errors + 1
            print(string.format("%s: markers differ at %s (%s / %s)", lang, here, markers(value), markers(theirs)))
        end
    end
    for key in pairs(other) do
        if base[key] == nil then
            errors = errors + 1
            print(lang .. ": extra " .. path .. "." .. tostring(key))
        end
    end
end

for lang, strings in pairs(i18n) do
    if lang ~= "pt" then
        compare(i18n.pt, strings, lang, lang)
    end
end
for lang, strings in pairs(i18n) do
    for key, value in pairs(strings) do
        if type(value) == "string" and (value:find("—") or value:find("–")) then
            errors = errors + 1
            print(lang .. ": dash in " .. key)
        end
    end
end
print(errors == 0 and "texts ok" or (errors .. " problems in the texts"))
os.exit(errors == 0 and 0 or 1)
