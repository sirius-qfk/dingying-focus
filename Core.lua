local addonName, G = ...
G.name = addonName
G.version = "0.2.0-alpha"
G.listeners = {}

function G.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = G.Copy(item) end
    return result
end

function G.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not G.Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function G.Finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Own SavedVariables only: reject cycles, non-data values and pathological depth
-- before copying a damaged profile. Never traverse arbitrary host frame graphs.
function G.ValidData(value)
    local active, count = {}, 0
    local function visit(item, depth)
        count = count + 1
        if count > 4096 or depth > 8 then return false end
        local kind = type(item)
        if kind == "number" then return G.Finite(item) end
        if kind ~= "table" then return kind == "nil" or kind == "string" or kind == "boolean" end
        if active[item] then return false end
        active[item] = true
        for key, child in pairs(item) do
            if (type(key) ~= "string" and not G.Finite(key)) or not visit(child, depth + 1) then return false end
        end
        active[item] = nil
        return true
    end
    return visit(value, 0)
end

function G.On(event, callback)
    G.listeners[event] = G.listeners[event] or {}
    table.insert(G.listeners[event], callback)
end

function G.Emit(event, ...)
    for _, callback in ipairs(G.listeners[event] or {}) do callback(...) end
end

function G.Message(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff40d6af梯度|r：" .. tostring(message)) end
end
