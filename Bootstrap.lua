local addonName, G = ...
local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
    events:RegisterEvent(event)
end

local function connect()
    if not G.Engine.db then return end
    G.Bridge:Install()
    local ok, err = G.Adapter.Probe()
    if not ok then G.Engine:Notify(err); return end
    G.Adapter.InstallHooks()
    G.Engine:Schedule("初始化")
end

events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        EllesmereUIGradientDB = EllesmereUIGradientDB or {}
        G.Engine:Init(EllesmereUIGradientDB)
    elseif event == "PLAYER_REGEN_DISABLED" then
        G.Regions:Hide()
        G.Engine:Notify("战斗中暂停布局修改，脱战后继续")
    elseif event == "PLAYER_LOGIN" then
        connect()
        -- Bounded readiness retries for EUI's deferred initialization; no polling loop.
        for _, delay in ipairs({ 0.5, 2, 5 }) do C_Timer.After(delay, connect) end
    elseif event == "ADDON_LOADED" then
        if name == "EllesmereUI" or name == "EllesmereUIOptions" or name == "EllesmereUIActionBars" or name == "EllesmereUICooldownManager" then
            C_Timer.After(0, connect)
        end
    else
        if event ~= "PLAYER_SPECIALIZATION_CHANGED" or name == "player" then
            G.Engine:Schedule(event)
        end
    end
end)

SLASH_ELLESMEREUIGRADIENT1 = "/eug"
SlashCmdList.ELLESMEREUIGRADIENT = function(command)
    if command == "status" then
        local available, reason = G.Adapter.Probe()
        G.Message(G.Engine.blocked or (available and G.Compatibility:Summary() or reason))
        local count = 0
        for _ in pairs(G.Engine.db and G.Engine.db.profiles or {}) do count = count + 1 end
        G.Message("已保留 " .. count .. " 份梯度配置；输入 /eug 打开设置")
        for _, b in ipairs(G.Bindings) do
            local target, reason = G.Adapter.Resolve(b)
            G.Message(b.label .. "：" .. (target and "接入点就绪（需游戏内验证）" or tostring(reason)))
        end
    else G.Bridge:Open() end
end
