local _, G = ...
local C = {}
G.Compatibility = C
G.ElementDrivers = {}

-- Private contracts are an explicit source-audited allowlist, NOT a promise from
-- EUI. Both versions remain alpha until the real-client release gates pass.
C.versions = {
    ["9.3"] = { settings = "legacy", action = "bars-1", cooldown = "cdm-1", controls = "rows-1" },
    ["9.4"] = { settings = "plugin", action = "bars-1", cooldown = "cdm-1", controls = "rows-1" },
}

function C:Version(addon)
    local v = C_AddOns and C_AddOns.GetAddOnMetadata(addon or "EllesmereUI", "Version")
    return type(v) == "string" and v:gsub("^v", "") or nil
end

function C:Probe()
    if not EllesmereUI then return nil, "EllesmereUI 未加载；梯度配置已保留" end
    if not self.versions[self:Version()] then
        return nil, "EUI " .. tostring(self:Version()) .. " 未验证，已暂停接管；梯度和恢复记录已保留"
    end
    if type(EllesmereUI._ModuleNS) ~= "table" then return nil, "EUI 模块尚未就绪" end
    return true
end

function C:Module(group)
    local ok, reason = self:Probe()
    if not ok then return nil, reason end
    local driver = G.ElementDrivers[group]
    if not driver then return nil, "未注册元素适配器" end
    if G.NativeControls and G.NativeControls.failures[group] then return nil, G.NativeControls.failures[group] end
    local v = self:Version(driver.addon)
    local contract = self.versions[v]
    if not contract or v ~= self:Version() or contract[group] ~= self.versions[self:Version()][group] then
        return nil, driver.addon .. " 版本未验证：" .. tostring(v)
    end
    local e, hostContract = EllesmereUI, self.versions[self:Version()]
    if hostContract.settings == "plugin" then
        if not G.SettingsHost or not G.SettingsHost:PublicAPI() then return nil, "官方梯度设置入口不可用，停止接管" end
        if not G.SettingsHost.registered then return nil, "梯度设置页尚未注册，停止接管" end
    elseif type(e.GetMainFrame) ~= "function" or type(e.RegisterOnShow) ~= "function" or type(e.RegisterOnHide) ~= "function" then
        return nil, "梯度设置入口不可用，停止接管"
    end
    -- Original numeric controls becoming tier links is mandatory, not an optional
    -- cosmetic integration. Never resize against an unknown control contract.
    if not self.versions[self:Version()].controls then return nil, "尺寸入口契约未验证，停止接管" end
    if EllesmereUI.Widgets and type(EllesmereUI.Widgets.DualRow) ~= "function" then
        return nil, "尺寸入口发生变化，停止接管"
    end
    return driver.Probe(EllesmereUI._ModuleNS)
end

function C:Stamp(group)
    local driver = G.ElementDrivers[group]
    return { contract = self.versions[self:Version()][group], host = self:Version(),
        component = self:Version(driver.addon) }
end

function C:CanReplay(group, stamp)
    if not self:Module(group) then return false end
    if type(stamp) ~= "table" then return false end
    local source, component = self.versions[stamp.host], self.versions[stamp.component]
    local current = self.versions[self:Version()]
    -- A matching string alone is insufficient: both source and destination
    -- releases must have been explicitly reviewed for this contract family.
    return source and component and source[group] == stamp.contract
        and component[group] == stamp.contract and current[group] == stamp.contract or false
end

function C:Summary()
    local ok, reason = self:Probe()
    return ok and ("EUI " .. self:Version() .. " · 源码适配 / 待游戏验收") or reason
end
