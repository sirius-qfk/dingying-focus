local _, G = ...
local A = {}
G.Adapter = A

function A.Stamp(group) return G.Compatibility:Stamp(group) end
function A.CanReplay(group, stamp) return G.Compatibility:CanReplay(group, stamp) end

function A.Probe()
    local ok, reason = G.Runtime.Probe()
    if not ok then return nil, reason end
    return G.Compatibility:Probe()
end

function A.LegacyStamp(group)
    return { contract = group == "action" and "bars-1" or "cdm-1", host = "9.3", component = "9.3" }
end

function A.SetCollapsed(on)
    return G.SettingsHost:SetCollapsed(on)
end

function A.Guard()
    local ok, err = A.Probe()
    if not ok then return nil, err end
    if EllesmereUI._unlockActive then return nil, "请先退出 EUI 解锁布局模式" end
    return true
end

function A.Context()
    local profile = EllesmereUI and EllesmereUI.GetActiveProfileName and EllesmereUI.GetActiveProfileName()
    profile = profile or (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    local spec = GetSpecialization and GetSpecialization()
    local specID = spec and GetSpecializationInfo and GetSpecializationInfo(spec) or 0
    local n = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUICooldownManager
    local layout = n and n.GetActiveLayoutName and n.GetActiveLayoutName() or "default"
    local character = UnitGUID and UnitGUID("player") or "character"
    -- Length-prefixed fields avoid collisions with names containing separators.
    local parts = {}
    for i, value in ipairs({ character, profile, specID, layout }) do
        value = tostring(value); parts[i] = #value .. ":" .. value
    end
    return table.concat(parts, "|")
end

function A.Resolve(binding, restoring)
    local ok, reason = G.Compatibility:Module(binding.module)
    if not ok then return nil, reason end
    local e = EllesmereUI
    local all = e and e._ModuleNS or {}
    local driver = G.ElementDrivers[binding.module]
    local t, err = driver.Resolve(all, binding, restoring)
    if not t then return nil, err end
    if not restoring then
        if not t.frame then return nil, "实际框体尚未创建" end
        if math.abs(t.frame:GetEffectiveScale() / UIParent:GetEffectiveScale() - 1) > 0.001 then
            return nil, "组件有独立缩放，首版暂不接管"
        end
        if e.IsUnlockAnchored and e.IsUnlockAnchored(t.elementKey) then return nil, "已有 EUI 锚定关系，保留原布局" end
        if (e.GetWidthMatchTarget and e.GetWidthMatchTarget(t.elementKey)) or (e.GetHeightMatchTarget and e.GetHeightMatchTarget(t.elementKey)) then
            return nil, "已有 EUI 尺寸联动，保留原布局"
        end
    end
    return t
end

function A.Fields(t, p)
    return G.ElementDrivers[t.binding.module].Fields(t, p)
end

function A.Refresh(t)
    G.ElementDrivers[t.binding.module].Refresh(t)
end

function A.Extent(t)
    local f = t.frame
    local ratio = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return { width = f:GetWidth() * ratio, height = f:GetHeight() * ratio }
end

function A.FrozenBounds(binding)
    local t = A.Resolve(binding, true)
    if not t or not t.frame or not t.frame.GetCenter then return nil end
    local x, y = t.frame:GetCenter()
    if not G.Finite(x) or not G.Finite(y) then return nil end
    local ratio = t.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    t.extent = A.Extent(t)
    t.position = { x = x * ratio - UIParent:GetWidth() / 2,
        y = y * ratio - UIParent:GetHeight() / 2 - t.extent.height / 2 }
    return t
end

function A.Place(t, pos)
    -- Position offsets use the relative frame's coordinate space; all regions use UIParent.
    t.frame:ClearAllPoints()
    t.frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

function A.Points(frame)
    local out = {}
    for i = 1, frame:GetNumPoints() do
        local point, relative, relPoint, x, y = frame:GetPoint(i)
        local name = relative and relative:GetName() or "UIParent"
        if not name then return nil, "原位置依赖匿名框体，暂不接管" end
        out[#out + 1] = { point, name, relPoint, x, y }
    end
    return out
end

function A.RestorePoints(frame, points)
    if not frame or not points then return end
    for _, point in ipairs(points) do if not _G[point[2]] then return end end
    frame:ClearAllPoints()
    for _, point in ipairs(points) do frame:SetPoint(point[1], _G[point[2]], point[3], point[4], point[5]) end
end

function A.LeaseRef(id)
    local b, field = A.LeaseBinding(id)
    if not b then return nil end
    local t = A.Resolve(b, true)
    if not t then return nil end
    if field == "position" then return { object = t.positions, key = b.key } end
    return { object = t.config, key = field }
end

function A.LeaseBinding(id)
    if type(id) ~= "string" then return nil end
    local target, field = id:match("^(.-)/(.+)$")
    for _, b in ipairs(G.Bindings) do
        if b.id == target then
            local allowed = b.module == "action" and { buttonWidth = true, buttonHeight = true, keybindFontSize = true, countFontSize = true }
                or { iconSize = true, cooldownFontSize = true, stackCountSize = true }
            if field == "position" or allowed[field] then return b, field end
        end
    end
end

function A.Watch(t)
    A.watched = A.watched or setmetatable({}, { __mode = "k" })
    if A.watched[t.frame] then return end
    A.watched[t.frame] = true
    local function changed()
        local engine = G.Engine
        if not engine or engine.busy or not engine.entry then return end
        if not engine.entry.enabled and not (engine.editing and engine.dirty) then return end
        for _, target in ipairs(engine.targets) do
            if target.frame == t.frame then
                if InCombatLockdown() or not A.PlacementMatches(target) then engine:Schedule("框体刷新") end
                return
            end
        end
    end
    t.frame:HookScript("OnSizeChanged", changed)
    G.PostHook(t.frame, "SetPoint", changed)
end

function A.PlacementMatches(t)
    if not t.position or not t.extent then return false end
    local point, relative, relPoint, x, y = t.frame:GetPoint(1)
    if type(point) ~= "string" or relative ~= UIParent or relPoint ~= t.position.relPoint then return false end
    if not G.Finite(x) or not G.Finite(y) then return false end
    local extent = A.Extent(t)
    -- EUI can re-express the same geometry using a growth corner. Compare the
    -- bottom-center location, not the anchor spelling; allow one physical pixel.
    if point:find("LEFT", 1, true) then x = x + extent.width / 2
    elseif point:find("RIGHT", 1, true) then x = x - extent.width / 2 end
    if point:find("TOP", 1, true) then y = y - extent.height
    elseif not point:find("BOTTOM", 1, true) then y = y - extent.height / 2 end
    local tolerance = 1 / UIParent:GetEffectiveScale() + 0.01
    return math.abs(x - t.position.x) < tolerance and math.abs(y - t.position.y) < tolerance
        and math.abs(extent.width - t.extent.width) < tolerance and math.abs(extent.height - t.extent.height) < tolerance
end

function A.InstallHooks()
    if not A.Probe() then return end
    local e = EllesmereUI
    local function changed()
        local engine = G.Engine
        if not engine or engine.busy or not engine.entry then return end
        if InCombatLockdown() then engine:Schedule("战斗后检查布局"); return end
        if A.Context() ~= engine.context then engine:Schedule("EUI 配置切换"); return end
        if not engine.entry.enabled and not (engine.editing and engine.dirty) then
            if next(engine.entry.applied.leases) then engine:Schedule("重试恢复") end
            return
        end
        for id, lease in pairs(engine.entry.applied.leases) do
            local ref = A.LeaseRef(id)
            if not engine.journal:Owns(id, ref) then engine:Schedule("EUI 设置变更"); return end
        end
        for _, target in ipairs(engine.targets) do
            if not A.PlacementMatches(target) then engine:Schedule("EUI 布局变更"); return end
        end
        for _, binding in ipairs(G.Bindings) do
            if not engine.entry.applied.leases[binding.id .. "/position"] and A.Resolve(binding) then
                engine:Schedule("EUI 新目标就绪"); return
            end
        end
    end
    for _, key in ipairs({ "SwitchProfile", "ApplyProfileData", "OnSpecSwitchComplete", "RefreshAllAddons", "RenameProfile", "DeleteProfile" }) do G.PostHook(e, key, changed) end
    for _, key in ipairs({ "_EAB_Apply", "_ECME_Apply", "_ECME_LoadSpecProfile" }) do G.PostHook(_G, key, changed) end
    local all = e and e._ModuleNS or {}
    local ab = all.EllesmereUIActionBars
    if ab and ab.EAB then
        G.PostHook(ab.EAB, "ApplyFontsForBar", changed)
        G.PostHook(ab.EAB, "ApplyButtonSizeForBar", changed)
    end
    local cd = all.EllesmereUICooldownManager
    if cd then
        G.PostHook(cd, "BuildAllCDMBars", changed)
        G.PostHook(cd, "RefreshCDMIconAppearance", changed)
        G.PostHook(cd, "ProcessSpecChange", changed)
    end
end
