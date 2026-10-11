local _, G = ...
local D = { addon = "EllesmereUICooldownManager" }
G.ElementDrivers.cooldown = D

function D.Probe(all)
    local ns = all.EllesmereUICooldownManager
    if type(ns) ~= "table" or type(ns.ECME) ~= "table" then return nil, "冷却模块未加载" end
    for _, key in ipairs({ "LayoutCDMBar", "RefreshCDMIconAppearance", "GetBarData", "GetCDMBarFrame" }) do
        if type(ns[key]) ~= "function" then return nil, "冷却组刷新接口不匹配：" .. key end
    end
    return true
end

local function hasFontOverride(settings)
    return type(settings) == "table" and (rawget(settings, "cooldownFontSize") ~= nil or rawget(settings, "stackCountSize") ~= nil)
end

function D.HasFontOverrides(t)
    local ns = t.ns
    local sd = ns.GetBarSpellData and ns.GetBarSpellData(t.binding.key)
    if hasFontOverride(t.config.barSpellSettings) or (sd and hasFontOverride(sd.barSettings)) then return true end
    local stores = { t.config.customActiveStates or {}, t.profile.customActiveStates or {},
        sd and sd.spellSettings or {},
        ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(t.binding.key, false) or {},
        ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs", false) or {} }
    for _, store in ipairs(stores) do
        for _, settings in pairs(store) do if hasFontOverride(settings) then return true end end
    end
    return false
end

function D.Resolve(all, binding, restoring)
    local ns = all.EllesmereUICooldownManager
    local t = { binding = binding, ns = ns, owner = ns.ECME, elementKey = "CDM_" .. binding.key }
    t.profile = t.owner.db and t.owner.db.profile
    if t.profile and type(t.profile.cdmBars) == "table" then
        for _, bar in ipairs(t.profile.cdmBars.bars or {}) do
            if bar.key == binding.key then t.config = bar; break end
        end
    end
    t.frame = ns.GetCDMBarFrame(binding.key)
    t.positions = t.profile and t.profile.cdmBarPositions
    if type(t.config) ~= "table" or type(t.positions) ~= "table" then return nil, "冷却组配置尚未就绪" end
    if not restoring then
        if not t.config.enabled then return nil, "该冷却组已关闭，未接管" end
        if ns.GetBarData(binding.key) ~= t.config then return nil, "冷却组正切换布局，请稍后重试" end
        if ns._pendingApplyOnReanchor then return nil, "冷却组尚在初始化，请稍后重试" end
        if t.config.anchorTo and t.config.anchorTo ~= "none" then return nil, "已有 EUI 锚定关系，保留原布局" end
        if (t.config.addOffsetX or 0) ~= 0 or (t.config.addOffsetY or 0) ~= 0 then return nil, "已有附加位移，保留原布局" end
        if t.config.customTopRowSizeEnabled or t.config.customBottomRowSizeEnabled then return nil, "已有分行图标尺寸，保留原布局" end
        if D.HasFontOverrides(t) then return nil, "存在单技能/分层字号覆盖，保留冷却组原设置" end
    end
    return t
end

function D.Fields(_, plan)
    return { iconSize = plan.icon, cooldownFontSize = plan.text, stackCountSize = plan.count }
end

function D.Refresh(t)
    t.ns.LayoutCDMBar(t.binding.key)
    t.ns.RefreshCDMIconAppearance(t.binding.key)
end
