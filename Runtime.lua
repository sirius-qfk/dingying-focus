local _, G = ...
G.Runtime = {}
function G.Runtime.Probe()
    if type(GetBuildInfo) ~= "function" then return nil, "无法确认游戏版本，已暂停接管" end
    local _, _, _, interface = GetBuildInfo()
    if interface ~= 120100 then return nil, "游戏接口版本未验证：" .. tostring(interface) .. "；配置已保留" end
    if type(InCombatLockdown) ~= "function" or type(hooksecurefunc) ~= "function"
        or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" or not UIParent then
        return nil, "游戏运行接口不完整，已暂停接管"
    end
    return true
end
function G.Runtime.InCombat() return InCombatLockdown() end
function G.Runtime.After(delay, callback) C_Timer.After(delay, callback) end

function G.Screen()
    if UIParent then return UIParent:GetWidth(), UIParent:GetHeight() end
    return 1920, 1080
end

-- Never replace host functions. One secure post-hook per observed function identity.
G.hooks = setmetatable({}, { __mode = "k" })
function G.PostHook(owner, key, callback)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" or not hooksecurefunc then return false end
    local slots = G.hooks[owner]
    if not slots then slots = {}; G.hooks[owner] = slots end
    if slots[key] == owner[key] then return true end
    hooksecurefunc(owner, key, callback)
    slots[key] = owner[key]
    return true
end
